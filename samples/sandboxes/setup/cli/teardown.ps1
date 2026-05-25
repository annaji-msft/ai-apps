# Sandboxes pillar - CLI teardown.
# Deletes the sandbox group, then the resource group. No Python required.

$ErrorActionPreference = 'Stop'

$SamplesDir = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$EnvFile = Join-Path $SamplesDir '.env'
if (Test-Path $EnvFile) {
    Get-Content $EnvFile | ForEach-Object {
        if ($_ -and -not $_.StartsWith('#') -and $_.Contains('=')) {
            $k, $v = $_.Split('=', 2)
            [Environment]::SetEnvironmentVariable($k.Trim(), $v.Trim(), 'Process')
        }
    }
}

$Yes = $args -contains '--yes'

$Sub = [Environment]::GetEnvironmentVariable('AZURE_SUBSCRIPTION_ID')
if ([string]::IsNullOrEmpty($Sub)) {
    $Sub = (az account show --query id -o tsv 2>$null)
}
$Rg  = [Environment]::GetEnvironmentVariable('ACA_RESOURCE_GROUP')
$Sbg = [Environment]::GetEnvironmentVariable('ACA_SANDBOX_GROUP')
if (-not $Rg -or -not $Sbg) {
    Write-Error "ACA_RESOURCE_GROUP / ACA_SANDBOX_GROUP not set - run setup.ps1 first?"
    exit 1
}

Write-Host "This will delete:"
Write-Host "  sandbox group:  $Sbg"
Write-Host "  resource group: $Rg (and ALL resources in it)"
if (-not $Yes) {
    $reply = Read-Host "Continue? [y/N]"
    if ($reply -notmatch '^(y|yes)$') { Write-Host "aborted."; exit 0 }
}

Write-Host "==> Deleting sandbox group '$Sbg'..."
try { aca sandboxgroup delete --name $Sbg --yes 2>$null | Out-Null } catch {}
$global:LASTEXITCODE = 0

Write-Host "==> Deleting resource group '$Rg' (background)..."
az group delete --subscription $Sub --name $Rg --yes --no-wait

Write-Host "==> Done. (Resource group deletion runs in the background.)"
