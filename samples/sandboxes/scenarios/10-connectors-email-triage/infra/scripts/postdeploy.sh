#!/usr/bin/env bash
# Post-deploy script for sandboxes-connectors-email-triage.
#
# Runs after `azd up` provisioned everything and `azd deploy` pushed
# the receiver container image. Wires the runtime auth bits that
# Bicep deliberately did not handle:
#
#   1. Fetches a Connector Gateway runtime API key (POST listApiKey),
#      scoped to the Teams MCP server config.
#   2. Sets that key as a secret on the receiver Container App and
#      adds it to the app's environment as CONNECTOR_GATEWAY_API_KEY.
#   3. Triggers a restart so the receiver loads the new env.
#   4. Generates OAuth consent URLs for both connections (Office 365
#      and Teams) and prints them. The user opens each in a browser
#      and signs in once.
#
# When the user finishes consenting to both connections, the trigger
# config starts firing on real emails and the end-to-end flow is live.
#
# Inputs come from azd outputs surfaced as env vars:
#   AZURE_SUBSCRIPTION_ID
#   AZURE_RESOURCE_GROUP
#   CONNECTOR_GATEWAY_NAME
#   OFFICE365_CONNECTION_NAME
#   TEAMS_CONNECTION_NAME
#   TEAMS_MCP_SERVER_CONFIG_NAME
#   RECEIVER_CONTAINER_APP_NAME
#   TENANT_ID

set -euo pipefail

API_VERSION="2026-05-01-preview"

# ---- 0. Sanity / inputs ---------------------------------------------------

require_var() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    echo "error: required env var not set: $name" >&2
    return 1
  fi
}

require_var AZURE_SUBSCRIPTION_ID
require_var AZURE_RESOURCE_GROUP
require_var CONNECTOR_GATEWAY_NAME
require_var OFFICE365_CONNECTION_NAME
require_var TEAMS_CONNECTION_NAME
require_var TEAMS_MCP_SERVER_CONFIG_NAME
require_var RECEIVER_CONTAINER_APP_NAME
require_var TENANT_ID

if ! command -v az >/dev/null 2>&1; then
  echo "error: az CLI not on PATH" >&2
  exit 1
fi

SIGNED_IN_OID="$(az ad signed-in-user show --query id -o tsv 2>/dev/null || true)"
if [[ -z "$SIGNED_IN_OID" ]]; then
  echo "warning: could not detect signed-in user objectId. Consent links will use a placeholder." >&2
  SIGNED_IN_OID="00000000-0000-0000-0000-000000000000"
fi

ARM="https://management.azure.com/subscriptions/${AZURE_SUBSCRIPTION_ID}/resourceGroups/${AZURE_RESOURCE_GROUP}/providers/Microsoft.Web/connectorGateways/${CONNECTOR_GATEWAY_NAME}"

# ---- 1. Fetch the Connector Gateway runtime API key ----------------------
echo "==> Fetching MCP runtime API key for '${TEAMS_MCP_SERVER_CONFIG_NAME}'..."
# An MCP-config-scoped, never-expiring key is the right shape for a
# long-running receiver. Rotate via az ad rest + listApiKey to roll.
KEY_RESPONSE="$(az rest \
  --method post \
  --uri "${ARM}/listApiKey?api-version=${API_VERSION}" \
  --body "{\"scope\": \"${TEAMS_MCP_SERVER_CONFIG_NAME}\", \"neverExpire\": true}" \
  --headers Content-Type=application/json)"

API_KEY="$(printf '%s' "$KEY_RESPONSE" | python3 -c 'import json,sys;print(json.load(sys.stdin).get("key",""))')"
if [[ -z "$API_KEY" ]]; then
  echo "error: listApiKey returned no key. Response: $KEY_RESPONSE" >&2
  exit 1
fi
echo "    got key (length=${#API_KEY})."

# ---- 2. Stamp the key onto the receiver Container App --------------------
echo "==> Writing CONNECTOR_GATEWAY_API_KEY secret onto receiver ${RECEIVER_CONTAINER_APP_NAME}..."
az containerapp secret set \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --name "$RECEIVER_CONTAINER_APP_NAME" \
  --secrets "connector-gateway-api-key=${API_KEY}" \
  --output none

az containerapp update \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --name "$RECEIVER_CONTAINER_APP_NAME" \
  --set-env-vars "CONNECTOR_GATEWAY_API_KEY=secretref:connector-gateway-api-key" \
  --output none

echo "    receiver restarted with new env."

# ---- 3. Generate consent links for the two connections ------------------
print_consent_link() {
  local conn_name="$1" label="$2"
  echo
  echo "==> Generating OAuth consent link for ${label} (${conn_name})..."
  local body
  body=$(cat <<EOF
{
  "parameters": [
    {
      "objectId": "${SIGNED_IN_OID}",
      "parameterName": "token",
      "redirectUrl": "https://portal.azure.com",
      "tenantId": "${TENANT_ID}"
    }
  ]
}
EOF
)
  local response
  response="$(az rest \
    --method post \
    --uri "${ARM}/connections/${conn_name}/listConsentLinks?api-version=${API_VERSION}" \
    --body "$body" \
    --headers Content-Type=application/json)"
  local link
  link="$(printf '%s' "$response" | python3 -c 'import json,sys;v=json.load(sys.stdin).get("value",[]);print(v[0].get("link","") if v else "")')"
  if [[ -z "$link" ]]; then
    echo "  warning: no link in response for ${label}: ${response}" >&2
    return
  fi
  echo "  ${label} consent URL:"
  echo "  ${link}"
}

print_consent_link "$OFFICE365_CONNECTION_NAME" "Office 365 (Outlook)"
print_consent_link "$TEAMS_CONNECTION_NAME" "Microsoft Teams"

# ---- 4. Final operator instructions --------------------------------------
cat <<'EOF'

============================================================================
NEXT STEPS
============================================================================

  1. Open each consent URL above in a browser.
  2. Sign in with the M365 account whose mailbox + Teams channel you want
     the triage flow to use. (Same account is fine for both, or use
     different accounts — the connection records who consented.)
  3. After both connections show "Authenticated" in the portal, the
     trigger config starts firing on every new email and the receiver
     posts a triage card to the configured Teams channel when the email
     is classified as "important".

  Verify quickly:  az rest \\
    --method get \\
    --uri "${ARM}/connections/${OFFICE365_CONNECTION_NAME}?api-version=${API_VERSION}" \\
    --query properties.overallStatus -o tsv

  Expected: "Connected".

  Tear it all down with:   azd down --purge --force --no-prompt

============================================================================
EOF
