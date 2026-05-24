# Getting Started — Azure Container Apps Sandboxes CLI
#
# End-to-end zero-to-sandbox script. Walks through the full setup:
#   1. az login check
#   2. Create resource group
#   3. Create sandbox group (sets active config)
#   4. Grant yourself the Data Owner role on the sandbox group
#   5. Verify with aca doctor
#   6. Create an Ubuntu sandbox and run a command
#   7. Clean up the sandbox (resource group + sandbox group are kept)
#
# Override defaults via env vars:
#   ACA_RESOURCE_GROUP        (default: aca-samples-rg)
#   ACA_SANDBOX_GROUP         (default: aca-samples-group)
#   ACA_SANDBOXGROUP_REGION   (default: eastus2)

$ErrorActionPreference = 'Stop'

$ResourceGroup = if ($env:ACA_RESOURCE_GROUP)      { $env:ACA_RESOURCE_GROUP }      else { 'aca-samples-rg' }
$SandboxGroup  = if ($env:ACA_SANDBOX_GROUP)       { $env:ACA_SANDBOX_GROUP }       else { 'aca-samples-group' }
$Region        = if ($env:ACA_SANDBOXGROUP_REGION) { $env:ACA_SANDBOXGROUP_REGION } else { 'eastus2' }

# 1. Verify Azure CLI login
Write-Host '==> Checking az login...'
$null = az account show 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Not logged in. Running 'az login'..."
    az login | Out-Null
}
$SubscriptionId = (az account show --query id -o tsv).Trim()
$PrincipalId    = (az ad signed-in-user show --query id -o tsv).Trim()
Write-Host "    subscription: $SubscriptionId"
Write-Host "    principal:    $PrincipalId"

# 2. Create resource group (idempotent)
Write-Host "==> Creating resource group '$ResourceGroup' in $Region..."
az group create --name $ResourceGroup --location $Region | Out-Null

# 3. Create sandbox group and set as active config
Write-Host "==> Creating sandbox group '$SandboxGroup'..."
aca sandboxgroup create `
    --name $SandboxGroup `
    --location $Region `
    --resource-group $ResourceGroup `
    --set-config

# 4. Grant the signed-in user Data Owner role on the sandbox group
Write-Host "==> Assigning 'Container Apps SandboxGroup Data Owner' role..."
try {
    aca sandboxgroup role create `
        --role 'Container Apps SandboxGroup Data Owner' `
        --principal-id $PrincipalId
} catch {
    Write-Host '    (role may already be assigned; continuing)'
}

# 5. Verify setup
Write-Host '==> Running aca doctor...'
aca doctor

# 6. Create a sandbox and run a command
Write-Host '==> Creating sandbox...'
$createOutput = aca sandbox create --disk ubuntu | Out-String
Write-Host $createOutput.TrimEnd()
$match = [regex]::Match($createOutput, '(?m)^Created sandbox:\s*(\S+)')
if (-not $match.Success) {
    throw 'Could not parse sandbox id from create output'
}
$SandboxId = $match.Groups[1].Value

try {
    Write-Host '==> Running command in sandbox...'
    aca sandbox exec --id $SandboxId -c 'echo hello world && uname -a'
}
finally {
    Write-Host "==> Deleting sandbox $SandboxId..."
    aca sandbox delete --id $SandboxId --yes | Out-Null
}

Write-Host '==> Done.'
