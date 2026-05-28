#!/usr/bin/env pwsh
# Postprovision hook (Windows / cross-platform PowerShell).
#
# azd has already created the resource group via infra/main.bicep.
# This hook delegates the rest (preview-API resources + OAuth consent)
# to the SAME imperative setup scripts that the README documents, so the
# azd path and the manual path stay in lock-step.
#
# Order matters:
#   1. samples/sandboxes/setup/python/setup.py        (sandboxes pillar baseline:
#                                                      sandbox group + MI off,
#                                                      Data Owner RBAC, .env)
#   2. samples/sandboxes/scenarios/10-connectors-triggers/setup/python/setup.py
#                                                     (connector gateway + MI,
#                                                      office365 connection,
#                                                      OAuth consent, ACLs,
#                                                      sandbox-group MI on)
#
# Each script is idempotent — safe to re-run after a partial failure.
# Per-run sandbox / trigger lifecycle stays in email-to-sandbox/python/run.py
# (intentionally ephemeral).

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

# infra/hooks/postprovision.ps1 -> repo root is 6 ".." segments.
$repoRoot = (Resolve-Path "$PSScriptRoot/../../../../../..").Path
$samplesDir = Join-Path $repoRoot "samples"
$envFile = Join-Path $samplesDir ".env"
$baselineSetup = Join-Path $samplesDir "sandboxes/setup/python/setup.py"
$baselineReqs = Join-Path $samplesDir "sandboxes/setup/python/requirements.txt"
$scenarioSetup = Join-Path $PSScriptRoot "../../setup/python/setup.py"
$scenarioReqs = Join-Path $PSScriptRoot "../../setup/python/requirements.txt"

# `azd env get-value` writes "ERROR: key not found..." to *stdout* (not
# stderr) and exits non-zero when a key is missing. A naive
# `$v = (azd env get-value $k 2>$null)` captures that error string as the
# value. This helper checks the exit code and returns $null on miss.
function Get-AzdEnv {
    param([string]$Key)
    $out = & azd env get-value $Key 2>$null
    if ($LASTEXITCODE -ne 0) { return $null }
    if (-not $out) { return $null }
    $out.Trim()
}

# ----- 0. Preflight: az / aca CLI + auth ----------------------------------
function Require-Tool {
    param([string]$Name, [string]$InstallHint)
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Required CLI '$Name' not found on PATH. $InstallHint"
    }
}

Require-Tool "az" "Install: https://learn.microsoft.com/cli/azure/install-azure-cli"
Require-Tool "python" "Install Python 3.10+ from https://www.python.org/downloads/"
Require-Tool "aca" "Install: https://github.com/microsoft/azure-container-apps/blob/main/docs/early/aca-cli/README.md"

try {
    $azAccount = az account show -o json | ConvertFrom-Json
} catch {
    throw "az CLI is not logged in. Run 'az login' and re-try 'azd up'."
}

# ----- 1. Resolve subscription + RG (azd is the source of truth) ----------
$sub = $env:AZURE_SUBSCRIPTION_ID
if (-not $sub) { $sub = (Get-AzdEnv "AZURE_SUBSCRIPTION_ID") }
if (-not $sub) { $sub = $azAccount.id }

$activeSub = $azAccount.id
if ($activeSub -ne $sub) {
    Write-Host "==> Pointing az CLI at subscription $sub (was $activeSub)" -ForegroundColor Yellow
    az account set --subscription $sub | Out-Null
}

$rg = $env:ACA_RESOURCE_GROUP
if (-not $rg) { $rg = (Get-AzdEnv "ACA_RESOURCE_GROUP") }
if (-not $rg) { $rg = (Get-AzdEnv "AZURE_RESOURCE_GROUP") }
if (-not $rg) { throw "Could not resolve resource group from azd env." }

# Read the RG's actual location and use it as the sandbox-group region.
# This prevents the sandboxes-pillar setup.py from trying to recreate the
# RG in a different region (InvalidResourceGroupLocation). It also means
# the sandbox group ends up in whatever region the user picked at
# 'azd up' time, regardless of the default.
$rgLocation = (az group show --name $rg --query location -o tsv 2>$null)
if (-not $rgLocation) {
    throw "Could not read location for resource group '$rg'. Did Bicep deployment succeed?"
}

# Sandbox groups are only available in a fixed set of regions. Bicep already
# enforces this for the RG via @allowed on the location parameter, but a
# pre-existing RG (created before the @allowed was added, or via a different
# tool) can still slip through here. Fail fast with a clear, actionable
# message so the user doesn't have to read a Python traceback.
$sandboxRegions = @(
    'australiaeast','brazilsouth','canadacentral','canadaeast','centralus',
    'eastasia','eastus2','francecentral','germanywestcentral','japaneast',
    'koreacentral','mexicocentral','northcentralus','northeurope','norwayeast',
    'polandcentral','southafricanorth','southeastasia','southindia',
    'spaincentral','swedencentral','switzerlandnorth','uksouth',
    'westcentralus','westus','westus2','westus3'
)
if ($sandboxRegions -notcontains $rgLocation.ToLowerInvariant()) {
    throw @"
Resource group '$rg' is in region '$rgLocation', which does not support
Microsoft.App/sandboxGroups.

Supported regions:
  $($sandboxRegions -join ', ')

To recover:
  1. azd down --purge             # removes the bad RG
  2. azd env set AZURE_LOCATION westus2
  3. azd up                       # provisions in a supported region
"@
}

$env:ACA_SANDBOXGROUP_REGION = $rgLocation
$env:ACA_REGION = $rgLocation
Write-Host "==> Using RG location '$rgLocation' as sandbox-group region (override with ACA_SANDBOXGROUP_REGION + azd up to change)." -ForegroundColor Cyan

# ----- 2. Interactivity preflight (OAuth needs a TTY) ---------------------
$interactive = -not [Console]::IsInputRedirected
if (-not $interactive) {
    Write-Host "==> stdin appears to be redirected; OAuth consent flow may fail." -ForegroundColor Yellow
    Write-Host "    If setup.py prompts and exits, re-run 'azd up' from an interactive shell." -ForegroundColor Yellow
}

Write-Host "==> azd postprovision: provisioning preview-API resources" -ForegroundColor Cyan
Write-Host "    subscription:    $sub"
Write-Host "    resource group:  $rg"
Write-Host "    (Bicep created only the RG; everything else uses preview APIs"
Write-Host "     for which Bicep types are not yet published.)"
Write-Host ""

# ----- 3. Seed samples/.env so setup.py finds subscription + RG -----------
function Set-EnvLine {
    param([string]$Path, [string]$Key, [string]$Value)
    if (-not $Value) { return }
    if (-not (Test-Path $Path)) {
        Set-Content -Path $Path -Value "# Seeded by azd postprovision`n$Key=$Value`n" -Encoding utf8
        return
    }
    $content = Get-Content $Path -Raw
    if ($content -match "(?m)^$([regex]::Escape($Key))=") {
        $evaluator = [System.Text.RegularExpressions.MatchEvaluator] { param($m) "${Key}=${Value}" }
        $rx = New-Object System.Text.RegularExpressions.Regex("(?m)^$([regex]::Escape($Key))=.*$")
        $content = $rx.Replace($content, $evaluator)
        Set-Content -Path $Path -Value $content -Encoding utf8 -NoNewline
    } else {
        Add-Content -Path $Path -Value "$Key=$Value"
    }
}

if (-not (Test-Path $envFile)) {
    Write-Host "    creating $envFile"
    New-Item -ItemType File -Path $envFile -Force | Out-Null
}

Set-EnvLine $envFile "AZURE_SUBSCRIPTION_ID" $sub
Set-EnvLine $envFile "ACA_SUBSCRIPTION" $sub
Set-EnvLine $envFile "ACA_RESOURCE_GROUP" $rg
Set-EnvLine $envFile "ACA_SANDBOXGROUP_REGION" $rgLocation
Set-EnvLine $envFile "ACA_REGION" $rgLocation

# Mirror any user-set azd overrides through to the setup.py child process
# as plain env vars (do NOT write them into samples/.env — setup.py is the
# source of truth for those keys and writes them back to samples/.env on
# success). Matches the sandbox-group pattern: setup.py reads defaults
# from its own environment.
foreach ($k in @(
    "ACA_SANDBOX_GROUP",
    "ACA_CONNECTOR_GATEWAY",
    "ACA_CONNECTOR_GATEWAY_REGION",
    "ACA_CONNECTOR_CONNECTION",
    "ACA_USER_EMAIL"
)) {
    $v = (Get-AzdEnv $k)
    if ($v) { Set-Item -Path "env:$k" -Value $v }
}

# ----- 4. Sandboxes-pillar baseline (sandbox group + MI + Data Owner) -----
Write-Host "==> [1/2] Sandboxes-pillar baseline (sandbox group + RBAC)..." -ForegroundColor Cyan
& python -m pip install --quiet --disable-pip-version-check -r $baselineReqs
if ($LASTEXITCODE -ne 0) { throw "pip install (baseline) failed" }
& python $baselineSetup
if ($LASTEXITCODE -ne 0) { throw "sandboxes baseline setup.py failed (exit=$LASTEXITCODE)" }

# ----- 5. Connector-trigger scenario setup (gateway + connection + OAuth)
Write-Host ""
Write-Host "==> [2/2] Connector-gateway scenario setup (gateway + connection + OAuth consent)..." -ForegroundColor Cyan
& python -m pip install --quiet --disable-pip-version-check -r $scenarioReqs
if ($LASTEXITCODE -ne 0) { throw "pip install (scenario) failed" }
& python $scenarioSetup
if ($LASTEXITCODE -ne 0) { throw "scenario setup.py failed (exit=$LASTEXITCODE)" }

# ----- 6. Mirror samples/.env -> azd env so `azd env get-values` is rich --
Write-Host ""
Write-Host "==> Mirroring connector keys into azd env..."
$mirror = @(
    "ACA_SANDBOX_GROUP",
    "ACA_SANDBOX_GROUP_PRINCIPAL_ID",
    "ACA_SANDBOXGROUP_REGION",
    "ACA_REGION",
    "ACA_CONNECTOR_GATEWAY",
    "ACA_CONNECTOR_GATEWAY_REGION",
    "ACA_CONNECTOR_GATEWAY_PRINCIPAL_ID",
    "ACA_CONNECTOR_GATEWAY_TENANT_ID",
    "ACA_CONNECTOR_CONNECTION",
    "ACA_CONNECTOR_CONNECTION_RUNTIME_URL",
    "ACA_USER_EMAIL"
)
foreach ($line in (Get-Content $envFile)) {
    if ($line -match "^\s*#" -or $line -notmatch "=") { continue }
    $kv = $line -split "=", 2
    $k = $kv[0].Trim()
    $v = $kv[1].Trim()
    if ($mirror -contains $k -and $v) {
        & azd env set $k $v | Out-Null
    }
}

Write-Host ""
Write-Host "==> azd postprovision: done." -ForegroundColor Green
Write-Host ""
Write-Host "Next, fire the end-to-end demo with:"
Write-Host "  cd email-to-sandbox/python; pip install -r requirements.txt; python run.py"
Write-Host "or:"
Write-Host "  bash email-to-sandbox/cli/run.sh"
