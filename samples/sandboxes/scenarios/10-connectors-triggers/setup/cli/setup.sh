#!/usr/bin/env bash
# Connector-gateway scenario - CLI setup (pure bash + az).
#
# Provisions:
#   1. Connector gateway with SystemAssigned MI
#      (Microsoft.Web/connectorGateways, ARM PUT via `az rest`)
#   2. Office 365 connection on the gateway
#   3. One-time OAuth consent flow (if connection isn't already Connected)
#   4. Access policy: gateway MI -> connection
#   5. Sandbox-group SystemAssigned MI + send-side access policy
#      (sandbox MI -> connection)
#   6. Declarative wiring on the sandbox group:
#      PATCH properties.gatewayConnections[] with
#      { resourceId, connectionRuntimeUrl, authentication.type=SystemAssignedManagedIdentity }.
#      Once this entry exists (and per-sandbox gatewayConnections lists
#      reference the same connection), the platform injects Bearer auth
#      automatically on every outbound call to the runtime URL.
#   7. Appends gateway / connection keys to samples/.env
#
# Flags:
#   --non-interactive    Don't open browser or wait for Enter. Exits with
#                        code 2 if OAuth consent is still required; re-run
#                        after completing consent.
#
# Prerequisites:
#   * Sandboxes baseline already provisioned
#     (samples/sandboxes/setup/{python,cli}/setup.{py,sh}).
#   * `az login` complete.
#
# Override defaults with environment variables:
#   ACA_CONNECTOR_GATEWAY            default: ai-apps-samples-gw
#   ACA_CONNECTOR_GATEWAY_REGION     default: ACA_SANDBOXGROUP_REGION
#                                    (from sandboxes pillar; e.g. westus2)
#   ACA_CONNECTOR_CONNECTION         default: o365-conn

set -euo pipefail

NON_INTERACTIVE=0
for arg in "$@"; do
    case "$arg" in
        --non-interactive|--non_interactive) NON_INTERACTIVE=1 ;;
        -h|--help) sed -n '2,33p' "$0"; exit 0 ;;
        *) echo "error: unknown argument: $arg" >&2; exit 1 ;;
    esac
done

API_VERSION="2026-05-01-preview"
# Sandbox-group ARM resource uses a different (older) API version that
# expresses properties.gatewayConnections[].
SANDBOXGROUP_API_VERSION="2026-02-01-preview"
CONNECTOR_NAME="office365"

: "${ACA_CONNECTOR_GATEWAY:=ai-apps-samples-gw}"
# ACA_CONNECTOR_GATEWAY_REGION defaults to the sandbox-group region after the
# samples/.env file is sourced below.
: "${ACA_CONNECTOR_CONNECTION:=o365-conn}"

# Prevent MSYS path mangling on Windows Git Bash (we pass /subscriptions/...
# to az rest --url and would otherwise get mangled into C:\Program Files\...).
export MSYS_NO_PATHCONV=1
export MSYS2_ARG_CONV_EXCL='*'

# ----- prereq: az login --------------------------------------------------
if ! command -v az >/dev/null 2>&1; then
    echo "error: azure CLI ('az') not found on PATH." >&2
    exit 1
fi

SUB="${AZURE_SUBSCRIPTION_ID:-$(az account show --query id -o tsv 2>/dev/null || true)}"
if [[ -z "$SUB" ]]; then
    echo "error: not logged in to Azure. Run 'az login' first." >&2
    exit 1
fi

# ----- load samples/.env (must already exist from sandboxes setup) -------
SAMPLES_DIR="$(cd "$(dirname "$0")/../../../../.." && pwd)"
ENV_FILE="$SAMPLES_DIR/.env"
if [[ ! -f "$ENV_FILE" ]]; then
    echo "error: $ENV_FILE not found." >&2
    echo "       Run the sandboxes pillar baseline first:" >&2
    echo "         ../../../sandboxes/setup/cli/setup.sh" >&2
    exit 1
fi
# shellcheck disable=SC1090
set -a; source "$ENV_FILE"; set +a

if [[ -z "${ACA_RESOURCE_GROUP:-}" ]]; then
    echo "error: ACA_RESOURCE_GROUP not in $ENV_FILE - run sandboxes setup." >&2
    exit 1
fi

# Default gateway region from the sandbox-group region (canonical key first,
# then the legacy ACA_REGION alias).
: "${ACA_CONNECTOR_GATEWAY_REGION:=${ACA_SANDBOXGROUP_REGION:-${ACA_REGION:-}}}"
if [[ -z "$ACA_CONNECTOR_GATEWAY_REGION" ]]; then
    echo "error: could not determine gateway region. Either set" >&2
    echo "       ACA_CONNECTOR_GATEWAY_REGION explicitly, or run the" >&2
    echo "       sandboxes pillar baseline first." >&2
    exit 1
fi

GW="$ACA_CONNECTOR_GATEWAY"
REGION="$ACA_CONNECTOR_GATEWAY_REGION"
CONN="$ACA_CONNECTOR_CONNECTION"
GW_URL_BASE="https://management.azure.com/subscriptions/$SUB/resourceGroups/$ACA_RESOURCE_GROUP/providers/Microsoft.Web/connectorGateways/$GW"

echo "==> Connector-gateway scenario - CLI setup"
echo "    subscription:    $SUB"
echo "    resource group:  $ACA_RESOURCE_GROUP"
echo "    gateway:         $GW"
echo "    gateway region:  $REGION"
echo "    connection:      $CONN ($CONNECTOR_NAME)"

# ----- temp-file helper (we register cleanup once with trap) -------------
TMPDIR_S="${TMPDIR:-/tmp}"
TMPFILES=()
mktmp() {
    local f
    f="$(mktemp "$TMPDIR_S/aca-trig-XXXXXX.json")"
    TMPFILES+=("$f")
    printf '%s' "$f"
}
cleanup_tmp() { rm -f "${TMPFILES[@]:-}" 2>/dev/null || true; }
trap cleanup_tmp EXIT

# ----- 1. Connector gateway ----------------------------------------------
echo "==> Ensuring connector gateway '$GW' in $REGION..."
GW_BODY_FILE="$(mktmp)"
cat > "$GW_BODY_FILE" <<EOF
{"location":"$REGION","identity":{"type":"SystemAssigned"}}
EOF
az rest \
    --method PUT \
    --url "$GW_URL_BASE?api-version=$API_VERSION" \
    --body "@$GW_BODY_FILE" >/dev/null

PRINCIPAL_ID="$(az rest \
    --method GET \
    --url "$GW_URL_BASE?api-version=$API_VERSION" \
    --query "identity.principalId" -o tsv)"
TENANT_ID="$(az rest \
    --method GET \
    --url "$GW_URL_BASE?api-version=$API_VERSION" \
    --query "identity.tenantId" -o tsv)"
if [[ -z "$PRINCIPAL_ID" || -z "$TENANT_ID" ]]; then
    echo "error: gateway has no system-assigned identity." >&2
    exit 1
fi
echo "    gateway MI principalId=$PRINCIPAL_ID"
echo "    gateway MI tenantId   =$TENANT_ID"

# ----- 2. Connection -----------------------------------------------------
echo "==> Ensuring '$CONNECTOR_NAME' connection '$CONN'..."
CONN_BODY_FILE="$(mktmp)"
cat > "$CONN_BODY_FILE" <<EOF
{"location":"$REGION","properties":{"connectorName":"$CONNECTOR_NAME"}}
EOF
az rest \
    --method PUT \
    --url "$GW_URL_BASE/connections/$CONN?api-version=$API_VERSION" \
    --body "@$CONN_BODY_FILE" >/dev/null

# ----- 3. Consent (if needed) --------------------------------------------
read_status() {
    az rest \
        --method GET \
        --url "$GW_URL_BASE/connections/$CONN?api-version=$API_VERSION" \
        --query "properties.statuses[0].status" -o tsv
}
STATUS="$(read_status)"
[[ -z "$STATUS" ]] && STATUS="Unknown"
echo "    connection status: $STATUS"

if [[ "$STATUS" != "Connected" ]]; then
    # Pull objectId/tenantId off the connection's createdBy block.
    CB_OBJ="$(az rest \
        --method GET \
        --url "$GW_URL_BASE/connections/$CONN?api-version=$API_VERSION" \
        --query "properties.createdBy.name" -o tsv 2>/dev/null || true)"
    if [[ -z "$CB_OBJ" ]]; then
        CB_OBJ="$(az rest \
            --method GET \
            --url "$GW_URL_BASE/connections/$CONN?api-version=$API_VERSION" \
            --query "properties.createdBy.objectId" -o tsv 2>/dev/null || true)"
    fi
    CB_TEN="$(az rest \
        --method GET \
        --url "$GW_URL_BASE/connections/$CONN?api-version=$API_VERSION" \
        --query "properties.createdBy.tenantId" -o tsv)"
    if [[ -z "$CB_OBJ" || -z "$CB_TEN" ]]; then
        echo "error: connection has no createdBy.{name,tenantId}; cannot build consent link." >&2
        exit 1
    fi

    CONSENT_BODY_FILE="$(mktmp)"
    cat > "$CONSENT_BODY_FILE" <<EOF
{"parameters":[{"objectId":"$CB_OBJ","tenantId":"$CB_TEN","redirectUrl":"https://microsoft.com","parameterName":"token"}]}
EOF
    LINK="$(az rest \
        --method POST \
        --url "$GW_URL_BASE/connections/$CONN/listConsentLinks?api-version=$API_VERSION" \
        --body "@$CONSENT_BODY_FILE" \
        --query "value[0].link" -o tsv)"
    if [[ -z "$LINK" ]]; then
        echo "error: listConsentLinks returned no link." >&2
        exit 1
    fi

    echo
    echo "========================================================================"
    echo "Office 365 connection needs OAuth consent."
    echo
    echo "  1. The link below is short-lived - click it IMMEDIATELY."
    echo "  2. Sign in with the account whose inbox you want to wire."
    echo "  3. After you see 'You may close this window', return here."
    echo
    echo "  Consent URL:"
    echo "  $LINK"
    echo "========================================================================"

    if [[ "$NON_INTERACTIVE" == "1" ]]; then
        echo
        echo "--non-interactive set; not opening browser or waiting."
        echo "Complete consent above, then re-run this script."
        exit 2
    fi

    # Best-effort browser launch (Windows / WSL / macOS / Linux).
    if command -v cmd.exe >/dev/null 2>&1; then
        cmd.exe /c start "" "$LINK" >/dev/null 2>&1 || true
    elif command -v open >/dev/null 2>&1; then
        open "$LINK" >/dev/null 2>&1 || true
    elif command -v xdg-open >/dev/null 2>&1; then
        xdg-open "$LINK" >/dev/null 2>&1 || true
    fi
    read -r -p "Press Enter once consent is complete... " _ || true

    for _ in 1 2 3 4 5 6; do
        STATUS="$(read_status)"
        [[ "$STATUS" == "Connected" ]] && break
        sleep 5
    done
    if [[ "$STATUS" != "Connected" ]]; then
        echo "error: connection still shows status '$STATUS'. Re-run setup; the consent link expires quickly." >&2
        exit 1
    fi
    echo "    connection status: $STATUS"
fi

# ----- 4. Access policy: gateway MI -> connection ------------------------
ensure_acl() {
    # ensure_acl <policy_name> <principal_id>
    local _name="$1"
    local _principal="$2"
    local _body_file
    _body_file="$(mktmp)"
    cat > "$_body_file" <<EOF
{"location":"$REGION","properties":{"principal":{"type":"ActiveDirectory","identity":{"objectId":"$_principal","tenantId":"$TENANT_ID"}}}}
EOF
    local _err
    if _err="$(az rest \
        --method PUT \
        --url "$GW_URL_BASE/connections/$CONN/accessPolicies/$_name?api-version=$API_VERSION" \
        --body "@$_body_file" 2>&1 >/dev/null)"; then
        echo "    access policy '$_name' applied"
    elif [[ "$_err" == *Exists* || "$_err" == *Conflict* ]]; then
        echo "    access policy '$_name' already exists (skipping)"
    else
        echo "error: access-policy '$_name' PUT failed:" >&2
        echo "$_err" >&2
        exit 1
    fi
}

echo "==> Granting gateway MI access policy on its own connection..."
ensure_acl "gateway-acl" "$PRINCIPAL_ID"

# ----- 4b. Sandbox-group SystemAssigned MI + send-side access policy -----
if ! command -v aca >/dev/null 2>&1; then
    echo "error: the 'aca' CLI is required for this setup but was not found on PATH." >&2
    echo "       Install it and retry:" >&2
    echo "         https://github.com/microsoft/azure-container-apps/blob/main/docs/early/aca-cli/README.md" >&2
    exit 1
fi

echo "==> Ensuring sandbox-group '$ACA_SANDBOX_GROUP' has SystemAssigned identity..."
read_sg_principal() {
    # `aca sandboxgroup identity show` returns identity-only JSON
    # ({principalId, tenantId, type}). Exits non-zero (with no JSON) if
    # the group has no identity yet — which is what we're probing for.
    # The resource group + subscription are read from `aca` CLI config
    # (or the ACA_RESOURCE_GROUP / ACA_SUBSCRIPTION env vars already in
    # samples/.env).
    aca sandboxgroup identity show --name "$ACA_SANDBOX_GROUP" -o json 2>/dev/null \
        | grep -oE '"principalId"[^"]*"[0-9a-fA-F-]+"' \
        | head -n1 \
        | sed -E 's/.*"([0-9a-fA-F-]+)".*/\1/'
}
SG_PRINCIPAL_ID="$(read_sg_principal || true)"
if [[ -z "$SG_PRINCIPAL_ID" ]]; then
    echo "    enabling SystemAssigned identity on '$ACA_SANDBOX_GROUP'..."
    aca sandboxgroup identity assign \
        --name "$ACA_SANDBOX_GROUP" --system-assigned \
        >/dev/null
    for _ in 1 2 3 4 5 6 7 8 9 10 11 12; do
        SG_PRINCIPAL_ID="$(read_sg_principal || true)"
        [[ -n "$SG_PRINCIPAL_ID" ]] && break
        sleep 2
    done
fi
if [[ -z "$SG_PRINCIPAL_ID" ]]; then
    echo "error: sandbox-group has no principalId after identity assign." >&2
    exit 1
fi
echo "    sandbox-group MI principalId=$SG_PRINCIPAL_ID"

echo "==> Granting sandbox-group MI access policy on the same connection (send-side)..."
ensure_acl "sandbox-acl" "$SG_PRINCIPAL_ID"

# ----- 4c. Fetch connection runtime URL ----------------------------------
echo "==> Resolving connection runtime URL..."
# Poll for up to 60s — connectionRuntimeUrl may not be set immediately
# after consent completes (the control plane mints it once the OAuth
# secret is in place).
RUNTIME_URL=""
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
    RUNTIME_URL="$(az rest \
        --method GET \
        --url "$GW_URL_BASE/connections/$CONN?api-version=$API_VERSION" \
        --query "properties.connectionRuntimeUrl" -o tsv 2>/dev/null || true)"
    if [[ -n "$RUNTIME_URL" && "$RUNTIME_URL" != "null" ]]; then break; fi
    sleep 3
done
if [[ -z "$RUNTIME_URL" || "$RUNTIME_URL" == "null" ]]; then
    echo "error: connection '$CONN' has no properties.connectionRuntimeUrl after 60s." >&2
    echo "       Wait ~30s and re-run setup." >&2
    exit 1
fi
RUNTIME_URL="${RUNTIME_URL%/}"
echo "    connectionRuntimeUrl: $RUNTIME_URL"

# ----- 4d. Wire connection on the sandbox group --------------------------
# GET-merge-PATCH properties.gatewayConnections[] on the sandbox group so
# it contains an entry { resourceId, connectionRuntimeUrl, authentication }
# for our connection, without clobbering any pre-existing entries (e.g.
# MCP servers added by other samples). With this entry in place AND each
# sandbox declaring the same resourceId in its own create body, the
# platform injects Bearer auth on every outbound call to the runtime URL
# automatically — no per-sandbox egress Transform rule required.
echo "==> Wiring connection on sandbox group '$ACA_SANDBOX_GROUP' (gatewayConnections[])..."
CONNECTION_RESOURCE_ID="/subscriptions/$SUB/resourceGroups/$ACA_RESOURCE_GROUP/providers/Microsoft.Web/connectorGateways/$GW/connections/$CONN"
SG_URL="https://management.azure.com/subscriptions/$SUB/resourceGroups/$ACA_RESOURCE_GROUP/providers/Microsoft.App/sandboxGroups/$ACA_SANDBOX_GROUP?api-version=$SANDBOXGROUP_API_VERSION"

SG_BODY_FILE="$(mktmp)"
az rest --method GET --url "$SG_URL" > "$SG_BODY_FILE"

SG_PATCH_BODY="$(mktmp)"
python3 - "$SG_BODY_FILE" "$CONNECTION_RESOURCE_ID" "$RUNTIME_URL" > "$SG_PATCH_BODY" <<'PYEOF'
import json, sys
sg_body_file, resource_id, runtime_url = sys.argv[1], sys.argv[2], sys.argv[3]
with open(sg_body_file, encoding="utf-8") as f:
    sg = json.load(f)
existing = list((sg.get("properties") or {}).get("gatewayConnections") or [])
rid_lower = resource_id.lower()
new_fields = {
    "resourceId": resource_id,
    "connectionRuntimeUrl": runtime_url,
    "authentication": {"type": "SystemAssignedManagedIdentity"},
}
merged = []
replaced = False
for e in existing:
    if (isinstance(e, dict)
            and isinstance(e.get("resourceId"), str)
            and e["resourceId"].lower() == rid_lower):
        # Merge into existing dict so future/unknown fields are preserved
        # across rewrites; resource IDs compared case-insensitively
        # because ARM treats them as such.
        merged.append({**e, **new_fields})
        replaced = True
    else:
        merged.append(e)
if not replaced:
    merged.append(dict(new_fields))
print(json.dumps({"properties": {"gatewayConnections": merged}}))
PYEOF
az rest --method PATCH --url "$SG_URL" --body "@$SG_PATCH_BODY" >/dev/null
echo "    sandbox-group gatewayConnections[] now references '$CONN'"

# ----- 5. Write samples/.env --------------------------------------------
echo "==> Writing $ENV_FILE..."
declare -A EXISTING
while IFS='=' read -r k v; do
    k="${k//$'\r'/}"
    k="${k%% *}"
    [[ -z "$k" || "${k:0:1}" == "#" ]] && continue
    EXISTING["$k"]="$v"
done < "$ENV_FILE"
EXISTING[ACA_CONNECTOR_GATEWAY]="$GW"
EXISTING[ACA_CONNECTOR_GATEWAY_REGION]="$REGION"
EXISTING[ACA_CONNECTOR_CONNECTION]="$CONN"
EXISTING[ACA_CONNECTOR_GATEWAY_PRINCIPAL_ID]="$PRINCIPAL_ID"
EXISTING[ACA_CONNECTOR_GATEWAY_TENANT_ID]="$TENANT_ID"
EXISTING[ACA_CONNECTOR_CONNECTION_RUNTIME_URL]="$RUNTIME_URL"
EXISTING[ACA_SANDBOX_GROUP_PRINCIPAL_ID]="$SG_PRINCIPAL_ID"

{
    echo "# Updated by samples/sandboxes/scenarios/10-connectors-triggers/setup/cli/setup.sh"
    echo "# Re-run sandbox or connector-trigger setup to update."
    echo ""
    for k in $(printf '%s\n' "${!EXISTING[@]}" | sort); do
        echo "$k=${EXISTING[$k]}"
    done
} > "$ENV_FILE"
echo "    wrote $ENV_FILE"

echo "==> Done."
echo "    Next: cd ../../trigger-lifecycle/cli && ./run.sh"
