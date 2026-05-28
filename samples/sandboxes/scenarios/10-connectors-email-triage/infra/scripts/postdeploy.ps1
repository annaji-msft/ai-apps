# Post-deploy script for sandboxes-connectors-email-triage (Windows).
# Mirrors infra/scripts/postdeploy.sh — see that file for the design notes.

$ErrorActionPreference = 'Stop'
$apiVersion = '2026-05-01-preview'

function Require-EnvVar([string]$Name) {
    $val = [System.Environment]::GetEnvironmentVariable($Name)
    if ([string]::IsNullOrEmpty($val)) {
        Write-Error "required env var not set: $Name"
    }
    return $val
}

$sub        = Require-EnvVar 'AZURE_SUBSCRIPTION_ID'
$rg         = Require-EnvVar 'AZURE_RESOURCE_GROUP'
$gw         = Require-EnvVar 'CONNECTOR_GATEWAY_NAME'
$o365Conn   = Require-EnvVar 'OFFICE365_CONNECTION_NAME'
$teamsConn  = Require-EnvVar 'TEAMS_CONNECTION_NAME'
$mcpName    = Require-EnvVar 'TEAMS_MCP_SERVER_CONFIG_NAME'
$rcv        = Require-EnvVar 'RECEIVER_CONTAINER_APP_NAME'
$tenantId   = Require-EnvVar 'TENANT_ID'

$signedInOid = (az ad signed-in-user show --query id -o tsv 2>$null)
if ([string]::IsNullOrEmpty($signedInOid)) {
    Write-Warning 'Could not detect signed-in user objectId; consent links will use a placeholder.'
    $signedInOid = '00000000-0000-0000-0000-000000000000'
}

$arm = "https://management.azure.com/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.Web/connectorGateways/$gw"

# ---- 1. Fetch the runtime API key ----------------------------------------
Write-Host "==> Fetching MCP runtime API key for '$mcpName'..."
$keyBody = @{ scope = $mcpName; neverExpire = $true } | ConvertTo-Json -Compress
$keyRespJson = az rest --method post --uri "$arm/listApiKey?api-version=$apiVersion" `
    --body $keyBody --headers Content-Type=application/json
$keyResp = $keyRespJson | ConvertFrom-Json
if (-not $keyResp.key) {
    Write-Error "listApiKey returned no 'key' field. Response was: $keyRespJson"
}
$apiKey = $keyResp.key
Write-Host "    got key (length=$($apiKey.Length))."

# ---- 2. Stamp it onto the receiver Container App -------------------------
Write-Host "==> Writing CONNECTOR_GATEWAY_API_KEY secret onto receiver $rcv..."
az containerapp secret set `
    --resource-group $rg --name $rcv `
    --secrets "connector-gateway-api-key=$apiKey" --output none

az containerapp update `
    --resource-group $rg --name $rcv `
    --set-env-vars "CONNECTOR_GATEWAY_API_KEY=secretref:connector-gateway-api-key" `
    --output none

Write-Host '    receiver restarted with new env.'

# ---- 3. Consent links ----------------------------------------------------
function Print-Consent([string]$ConnName, [string]$Label) {
    Write-Host ""
    Write-Host "==> Generating OAuth consent link for $Label ($ConnName)..."
    $body = @{
        parameters = @(
            @{
                objectId      = $signedInOid
                parameterName = 'token'
                redirectUrl   = 'https://portal.azure.com'
                tenantId      = $tenantId
            }
        )
    } | ConvertTo-Json -Compress -Depth 5

    $respJson = az rest --method post `
        --uri "$arm/connections/$ConnName/listConsentLinks?api-version=$apiVersion" `
        --body $body --headers Content-Type=application/json
    $resp = $respJson | ConvertFrom-Json
    $link = $resp.value | Select-Object -First 1 -ExpandProperty link
    if (-not $link) {
        Write-Warning "no link in response for $Label : $respJson"
        return
    }
    Write-Host "  $Label consent URL:"
    Write-Host "  $link"
}

Print-Consent $o365Conn 'Office 365 (Outlook)'
Print-Consent $teamsConn 'Microsoft Teams'

# ---- 4. Operator wrap-up -------------------------------------------------
Write-Host ''
Write-Host '============================================================================'
Write-Host 'NEXT STEPS'
Write-Host '============================================================================'
Write-Host '  1. Open each consent URL above in a browser.'
Write-Host '  2. Sign in with the M365 account whose mailbox + Teams channel you want'
Write-Host '     the triage flow to use.'
Write-Host '  3. After both connections show "Authenticated" in the portal, the'
Write-Host '     trigger config starts firing on every new email and the receiver'
Write-Host '     posts a triage card to the configured Teams channel when the email'
Write-Host '     is classified as "important".'
Write-Host ''
Write-Host "  Verify Office 365 status:  az rest --method get --uri ""$arm/connections/$o365Conn`?api-version=$apiVersion"" --query properties.overallStatus -o tsv"
Write-Host ''
Write-Host '  Tear it all down with:   azd down --purge --force --no-prompt'
Write-Host '============================================================================'
