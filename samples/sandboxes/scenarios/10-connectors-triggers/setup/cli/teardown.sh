#!/usr/bin/env bash
# Tear down the connector-gateway baseline (CLI flow).
#
# Deletes the connector gateway (along with all its connections, trigger
# configs, and access policies), removes the scenario's entry from the
# sandbox group's properties.gatewayConnections[] (preserving any other
# entries like MCP servers), then clears the trigger-related keys
# from samples/.env.
#
# Does NOT touch the sandboxes baseline (resource group, sandbox group itself).
#
#   ./teardown.sh        # interactive
#   ./teardown.sh --yes  # skip confirmation

set -euo pipefail
export MSYS_NO_PATHCONV=1
export MSYS2_ARG_CONV_EXCL='*'

API_VERSION="2026-05-01-preview"
SANDBOXGROUP_API_VERSION="2026-02-01-preview"

SAMPLES_DIR="$(cd "$(dirname "$0")/../../../../.." && pwd)"
ENV_FILE="$SAMPLES_DIR/.env"
if [[ ! -f "$ENV_FILE" ]]; then
    echo "error: $ENV_FILE not found - nothing to tear down." >&2
    exit 1
fi
# shellcheck disable=SC1090
set -a; source "$ENV_FILE"; set +a

SUB="${AZURE_SUBSCRIPTION_ID:-$(az account show --query id -o tsv 2>/dev/null || true)}"
RG="${ACA_RESOURCE_GROUP:-}"
GW="${ACA_CONNECTOR_GATEWAY:-}"
CONN="${ACA_CONNECTOR_CONNECTION:-}"
SG="${ACA_SANDBOX_GROUP:-}"
if [[ -z "$SUB" || -z "$RG" || -z "$GW" ]]; then
    echo "error: $ENV_FILE missing trigger keys - was connector-gateway setup run?" >&2
    exit 1
fi

echo "This will delete:"
echo "  connector gateway: $GW (and all its connections + trigger configs)"
if [[ -n "$SG" && -n "$CONN" ]]; then
    echo "  gatewayConnections[] entry for '$CONN' on sandbox group '$SG'"
fi
echo "  trigger-related keys from $ENV_FILE"
echo
echo "It will NOT delete the resource group or sandbox group."
case "${1:-}" in
    --yes|-y)
        ;;
    *)
        read -r -p "Continue? [y/N] " reply
        case "${reply,,}" in
            y|yes) ;;
            *) echo "aborted."; exit 0 ;;
        esac
        ;;
esac

# Remove the sandbox-group wiring FIRST, while the connection resourceId
# is still resolvable. After gateway delete the resource is gone and the
# SG entry would be a dangling reference.
if [[ -n "$SG" && -n "$CONN" ]]; then
    echo "==> Removing gatewayConnections entry from sandbox group '$SG'..."
    CONNECTION_RESOURCE_ID="/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.Web/connectorGateways/$GW/connections/$CONN"
    SG_URL="https://management.azure.com/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.App/sandboxGroups/$SG?api-version=$SANDBOXGROUP_API_VERSION"
    if SG_BODY="$(az rest --method GET --url "$SG_URL" 2>&1)"; then
        PATCH_BODY_FILE="$(mktemp -t aca-trig-td-XXXXXX.json)"
        ACTION="$(python3 - "$SG_BODY" "$CONNECTION_RESOURCE_ID" "$PATCH_BODY_FILE" <<'PYEOF'
import json, sys
sg = json.loads(sys.argv[1] or "{}")
resource_id = sys.argv[2]
patch_file = sys.argv[3]
existing = list((sg.get("properties") or {}).get("gatewayConnections") or [])
# ARM resource IDs are case-insensitive; lowercase for the compare so we
# still remove an entry written by a setup run that used different
# casing for sub/rg/gateway/connection segments.
rid_lower = resource_id.lower()
remaining = [e for e in existing
             if not (isinstance(e, dict)
                     and isinstance(e.get("resourceId"), str)
                     and e["resourceId"].lower() == rid_lower)]
with open(patch_file, "w", encoding="utf-8") as f:
    json.dump({"properties": {"gatewayConnections": remaining}}, f)
print("removed" if len(remaining) != len(existing) else "noop")
PYEOF
)"
        if [[ "$ACTION" == "removed" ]]; then
            if az rest --method PATCH --url "$SG_URL" --body "@$PATCH_BODY_FILE" >/dev/null 2>&1; then
                echo "    removed gatewayConnections entry for '$CONN'"
            else
                echo "    warning: PATCH sandbox group failed; entry may be stale"
            fi
        else
            echo "    sandbox group has no gatewayConnections entry for this connection (skipping)"
        fi
        rm -f "$PATCH_BODY_FILE" 2>/dev/null || true
    else
        if [[ "$SG_BODY" == *NotFound* || "$SG_BODY" == *ResourceNotFound* || "$SG_BODY" == *404* ]]; then
            echo "    sandbox group '$SG' not found (skipping)"
        else
            echo "    warning: GET sandbox group failed; skipping cleanup"
        fi
    fi
fi

URL="https://management.azure.com/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.Web/connectorGateways/$GW?api-version=$API_VERSION"
echo "==> Deleting connector gateway '$GW'..."
if ERR="$(az rest --method DELETE --url "$URL" 2>&1)"; then
    :
elif [[ "$ERR" == *NotFound* || "$ERR" == *ResourceNotFound* || "$ERR" == *404* ]]; then
    echo "    not found (already deleted)"
else
    echo "error: az rest DELETE failed:" >&2
    echo "$ERR" >&2
    exit 1
fi

echo "==> Updating $ENV_FILE..."
declare -A KEPT
TRIGGER_KEYS=(ACA_CONNECTOR_GATEWAY ACA_CONNECTOR_GATEWAY_REGION ACA_CONNECTOR_CONNECTION ACA_CONNECTOR_GATEWAY_PRINCIPAL_ID ACA_CONNECTOR_GATEWAY_TENANT_ID ACA_CONNECTOR_CONNECTION_RUNTIME_URL ACA_SANDBOX_GROUP_PRINCIPAL_ID)
is_trigger_key() {
    local needle="$1" k
    for k in "${TRIGGER_KEYS[@]}"; do
        [[ "$k" == "$needle" ]] && return 0
    done
    return 1
}
while IFS='=' read -r k v; do
    k="${k//$'\r'/}"
    k="${k%% *}"
    [[ -z "$k" || "${k:0:1}" == "#" ]] && continue
    is_trigger_key "$k" && continue
    KEPT["$k"]="$v"
done < "$ENV_FILE"
{
    echo "# Updated by samples/sandboxes/scenarios/10-connectors-triggers/setup/cli/teardown.sh"
    echo "# Re-run sandbox or connector-trigger setup to update."
    echo ""
    for k in $(printf '%s\n' "${!KEPT[@]}" | sort); do
        echo "$k=${KEPT[$k]}"
    done
} > "$ENV_FILE"
echo "    wrote $ENV_FILE (dropped ${#TRIGGER_KEYS[@]} trigger keys)"
echo "==> Done."
