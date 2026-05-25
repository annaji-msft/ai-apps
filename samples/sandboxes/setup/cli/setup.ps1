# Sandboxes pillar - CLI setup (no Python required).
#
# Provisions:
#   1. Resource group              (az group create)
#   2. aca CLI installed           (official install script)
#   3. CLI config defaults         (aca config set / aca config sandbox set)
#   4. Sandbox group               (aca sandboxgroup create --set-config)
#   5. Data-owner role assignment  (aca sandboxgroup role create)
#   6. samples/.env                (so Python guides can read the same config)
#   7. aca doctor                  (verifies everything)
#
# Override defaults with environment variables:
#   AZURE_SUBSCRIPTION_ID      (auto-detected from `az account show`)
#   ACA_RESOURCE_GROUP         default: ai-apps-samples-rg
#   ACA_SANDBOX_GROUP          default: ai-apps-samples-group
#   ACA_SANDBOXGROUP_REGION    default: westus2

$ErrorActionPreference = 'Stop'

$RoleName = 'Container Apps SandboxGroup Data Owner'
$CliInstallUrl = 'https://raw.githubusercontent.com/microsoft/azure-container-apps/main/docs/early/aca-cli/install.ps1'

function _envOrDefault($name, $default) {
    $v = [Environment]::GetEnvironmentVariable($name)
    if ([string]::IsNullOrEmpty($v)) { return $default } else { return $v }
}

$ResourceGroup = _envOrDefault 'ACA_RESOURCE_GROUP' 'ai-apps-samples-rg'
$SandboxGroup  = _envOrDefault 'ACA_SANDBOX_GROUP'  'ai-apps-samples-group'
$Region        = _envOrDefault 'ACA_SANDBOXGROUP_REGION' 'westus2'
$AcaRegion     = _envOrDefault 'ACA_REGION' $Region

# ----- prereq: az login --------------------------------------------------
if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    Write-Error "Azure CLI ('az') not found on PATH. Install from https://learn.microsoft.com/cli/azure/install-azure-cli"
    exit 1
}

$Sub = [Environment]::GetEnvironmentVariable('AZURE_SUBSCRIPTION_ID')
if ([string]::IsNullOrEmpty($Sub)) {
    $Sub = (az account show --query id -o tsv 2>$null)
}
if ([string]::IsNullOrEmpty($Sub)) {
    Write-Error "Not logged in to Azure. Run 'az login' first."
    exit 1
}

Write-Host "==> Sandboxes pillar - CLI setup"
Write-Host "    subscription:   $Sub"
Write-Host "    resource group: $ResourceGroup"
Write-Host "    sandbox group:  $SandboxGroup"
Write-Host "    region:         $Region"

# ----- 1. Resource group -------------------------------------------------
Write-Host "==> Ensuring resource group '$ResourceGroup' in $Region..."
az group create --subscription $Sub --name $ResourceGroup --location $Region --output none

# ----- 2. Install aca CLI ------------------------------------------------
if (-not (Get-Command aca -ErrorAction SilentlyContinue)) {
    Write-Host "==> Installing the aca CLI..."
    $ProgressPreference = 'SilentlyContinue'
    & ([scriptblock]::Create((Invoke-RestMethod $CliInstallUrl)))
    $env:PATH = "$HOME\.aca\bin;$env:PATH"
}
if (-not (Get-Command aca -ErrorAction SilentlyContinue)) {
    Write-Error "'aca' is still not on PATH after install. Add '$HOME\.aca\bin' to PATH and re-run."
    exit 1
}
$version = (aca --version 2>&1 | Out-String).Trim()
Write-Host "    $version"

# ----- 3. CLI shared defaults --------------------------------------------
Write-Host "==> aca config set ... (shared defaults)"
aca config set --subscription $Sub --resource-group $ResourceGroup --region $Region | Out-Null

# ----- 4. Sandbox group --------------------------------------------------
Write-Host "==> Ensuring sandbox group '$SandboxGroup'..."
# --set-config saves group + region under the sandbox-specific config block.
$createOk = $true
try {
    aca sandboxgroup create --name $SandboxGroup --location $Region --set-config 2>$null | Out-Null
} catch {
    $createOk = $false
}
if (-not $createOk -or $LASTEXITCODE -ne 0) {
    Write-Host "    sandbox group already exists (saving config explicitly)"
    aca config sandbox set --group $SandboxGroup --region $Region | Out-Null
}
$global:LASTEXITCODE = 0

# ----- 5. RBAC ----------------------------------------------------------
Write-Host "==> Assigning '$RoleName'..."
$PrincipalId = (az ad signed-in-user show --query id -o tsv 2>$null)
if ([string]::IsNullOrEmpty($PrincipalId)) {
    # Fallback: parse oid from the management-plane access token.
    $token = (az account get-access-token --resource 'https://management.azure.com/' --query accessToken -o tsv)
    $payload = $token.Split('.')[1].Replace('-','+').Replace('_','/')
    while ($payload.Length % 4) { $payload += '=' }
    $json = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($payload))
    $claims = $json | ConvertFrom-Json
    $PrincipalId = $claims.oid
}
if ([string]::IsNullOrEmpty($PrincipalId)) {
    Write-Warning "Could not determine principal id. Run manually:"
    Write-Warning "  aca sandboxgroup role create --role `"$RoleName`" --principal-id <your-oid>"
} else {
    aca sandboxgroup role create --role $RoleName --principal-id $PrincipalId 2>&1 |
        Where-Object { $_ -notmatch 'already|Exists' } | Out-Null
    $global:LASTEXITCODE = 0
    Write-Host "    assigned to $PrincipalId"
}

# ----- 6. samples/.env --------------------------------------------------
$SamplesDir = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$EnvFile = Join-Path $SamplesDir '.env'
Write-Host "==> Writing $EnvFile..."

$existing = [ordered]@{}
if (Test-Path $EnvFile) {
    Get-Content $EnvFile | ForEach-Object {
        if ($_ -and -not $_.StartsWith('#') -and $_.Contains('=')) {
            $k, $v = $_.Split('=', 2)
            $existing[$k.Trim()] = $v.Trim()
        }
    }
}
$existing['AZURE_SUBSCRIPTION_ID']    = $Sub
$existing['ACA_SUBSCRIPTION']         = $Sub
$existing['ACA_RESOURCE_GROUP']       = $ResourceGroup
$existing['ACA_SANDBOX_GROUP']        = $SandboxGroup
$existing['ACA_SANDBOXGROUP_REGION']  = $Region
$existing['ACA_REGION']               = $AcaRegion

$lines = @(
    '# Written by samples/sandboxes/setup/cli/setup.ps1'
    '# Re-run python or cli setup to update.'
    ''
)
foreach ($k in ($existing.Keys | Sort-Object)) {
    $lines += "$k=$($existing[$k])"
}
Set-Content -Path $EnvFile -Value $lines -Encoding utf8
Write-Host "    wrote $EnvFile"

# ----- 7. Doctor --------------------------------------------------------
Write-Host "==> aca doctor ..."
aca doctor

Write-Host "==> Done."
Write-Host "    Next: cd ..\..\guides\01-getting-started\cli ; .\run.ps1"
