#!/usr/bin/env bash
# Trigger lifecycle CRUD demo (aca CLI + az rest).
#
# Mirrors ../python/trigger.py. Walks the four primitive trigger operations:
#   1. Discover trigger operations on office365.
#   2. Create a sandbox + a tiny Python webhook listener on :5000.
#   3. Add port 5000 with gateway MI in entraId.objectIds.
#   4. PUT a trigger config (InvokePort).
#   5. List / disable / enable the trigger config.
#   6. Tear everything down (trigger -> port -> sandbox).

set -euo pipefail

# git-bash on Windows rewrites POSIX paths; suppress for /app and ARM URLs.
export MSYS_NO_PATHCONV=1
export MSYS2_ARG_CONV_EXCL='*'

API_VERSION="2026-05-01-preview"
PORT=5000
CONFIG_NAME="trigger-lifecycle-demo"

# ----- load samples/.env -------------------------------------------------
here="$(cd "$(dirname "$0")" && pwd)"
dir="$here"
while [[ "$dir" != "/" && ! -f "$dir/.env" ]]; do
    dir="$(dirname "$dir")"
done
if [[ ! -f "$dir/.env" ]]; then
    echo "error: could not find samples/.env - run setup first." >&2
    exit 1
fi
set -a; . "$dir/.env"; set +a

for v in AZURE_SUBSCRIPTION_ID ACA_RESOURCE_GROUP ACA_SANDBOX_GROUP \
         ACA_CONNECTOR_GATEWAY ACA_CONNECTOR_CONNECTION \
         ACA_CONNECTOR_GATEWAY_PRINCIPAL_ID; do
    if [[ -z "${!v:-}" ]]; then
        echo "error: missing env var '$v' (run both setup scripts)." >&2
        exit 1
    fi
done

SUB="$AZURE_SUBSCRIPTION_ID"
RG="$ACA_RESOURCE_GROUP"
SG="$ACA_SANDBOX_GROUP"
GW="$ACA_CONNECTOR_GATEWAY"
CONN="$ACA_CONNECTOR_CONNECTION"
GW_PRINCIPAL="$ACA_CONNECTOR_GATEWAY_PRINCIPAL_ID"
USER_EMAIL="${ACA_USER_EMAIL:-}"

ARM_BASE="https://management.azure.com/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.Web/connectorGateways/$GW"

# ----- temp-file helper --------------------------------------------------
TMPDIR_S="${TMPDIR:-/tmp}"
TMPFILES=()
mktmp() {
    local f
    f="$(mktemp "$TMPDIR_S/aca-trig-lifecycle-XXXXXX.json")"
    TMPFILES+=("$f")
    printf '%s' "$f"
}

SANDBOX_ID=""
PORT_ADDED=0
TRIGGER_CREATED=0

cleanup() {
    # Cleanup order: trigger -> port -> sandbox.
    if [[ "$TRIGGER_CREATED" == "1" ]]; then
        echo "==> DELETE trigger config '$CONFIG_NAME'"
        az rest --method DELETE \
            --url "$ARM_BASE/triggerConfigs/$CONFIG_NAME?api-version=$API_VERSION" \
            >/dev/null 2>&1 || echo "    warning: trigger delete failed"
    fi
    if [[ -n "$SANDBOX_ID" && "$PORT_ADDED" == "1" ]]; then
        echo "==> aca sandbox port remove --port $PORT"
        aca sandbox port remove --id "$SANDBOX_ID" --port "$PORT" >/dev/null 2>&1 \
            || echo "    warning: port remove failed"
    fi
    if [[ -n "$SANDBOX_ID" ]]; then
        echo "==> aca sandbox delete --id $SANDBOX_ID"
        aca sandbox delete --id "$SANDBOX_ID" --yes >/dev/null 2>&1 \
            || echo "    warning: sandbox delete failed"
    fi
    rm -f "${TMPFILES[@]:-}" 2>/dev/null || true
}
trap cleanup EXIT

# ----- 1. Discover trigger operations ------------------------------------
echo "==> 1. Discovering trigger operations for office365..."
LOC="$(az rest \
    --method GET \
    --url "$ARM_BASE?api-version=$API_VERSION" \
    --query "location" -o tsv)"
[[ -z "$LOC" ]] && LOC="${ACA_CONNECTOR_GATEWAY_REGION:-${ACA_SANDBOXGROUP_REGION:-${ACA_REGION:-}}}"
if [[ -z "$LOC" ]]; then
    echo "error: could not determine gateway location and no fallback region available" >&2
    exit 1
fi

# Pick OnNewEmailV3 if available, else fall back to the first trigger op.
OPS_URL="https://management.azure.com/subscriptions/$SUB/providers/Microsoft.Web/locations/$LOC/managedApis/office365/apiOperations?api-version=2016-06-01"
COUNT="$(az rest --method GET --url "$OPS_URL" \
    --query "length(value[?properties.trigger != null])" -o tsv 2>/dev/null || echo 0)"
echo "    $COUNT trigger operations available on office365"

OP_NAME="$(az rest --method GET --url "$OPS_URL" \
    --query "value[?properties.trigger != null && name=='OnNewEmailV3'].name | [0]" \
    -o tsv 2>/dev/null || true)"
if [[ -z "$OP_NAME" ]]; then
    OP_NAME="$(az rest --method GET --url "$OPS_URL" \
        --query "value[?properties.trigger != null].name | [0]" -o tsv)"
fi
echo "    using: $OP_NAME"

# ----- 2. Sandbox + listener ---------------------------------------------
echo "==> 2. Creating sandbox in '$SG'..."
CREATE_OUTPUT="$(aca sandbox create --group "$SG" --disk ubuntu)"
SANDBOX_ID="$(echo "$CREATE_OUTPUT" | sed -n 's/^Created sandbox: //p' | tail -n1)"
if [[ -z "$SANDBOX_ID" ]]; then
    SANDBOX_ID="$(echo "$CREATE_OUTPUT" | grep -oE 'sandbox-[a-z0-9-]+' | head -n1 || true)"
fi
[[ -n "$SANDBOX_ID" ]] || { echo "error: could not parse sandbox id from:" >&2; echo "$CREATE_OUTPUT" >&2; exit 1; }
echo "    sandbox: $SANDBOX_ID"

echo "==> Uploading + starting webhook listener on :$PORT..."
SERVER_FILE="$(mktmp)"
cat > "$SERVER_FILE" <<'PY'
import http.server, sys
class H(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        n = int(self.headers.get("Content-Length", "0") or 0)
        body = self.rfile.read(n).decode("utf-8", "replace") if n else ""
        sys.stdout.write(f"WEBHOOK {self.path} body={body[:120]}\n"); sys.stdout.flush()
        self.send_response(200); self.send_header("Content-Type","application/json"); self.end_headers()
        self.wfile.write(b'{"ok":true}')
    def log_message(self, *a, **k): pass
print("listening on :5000", flush=True)
http.server.HTTPServer(("0.0.0.0", 5000), H).serve_forever()
PY

# Native path for aca CLI on Windows (cygpath).
to_native() {
    if command -v cygpath >/dev/null 2>&1; then cygpath -w "$1"; else echo "$1"; fi
}

aca sandbox exec --group "$SG" --id "$SANDBOX_ID" -c "mkdir -p /app" >/dev/null
aca sandbox fs write --group "$SG" --id "$SANDBOX_ID" --path /app/server.py \
    --file "$(to_native "$SERVER_FILE")" >/dev/null
aca sandbox exec --group "$SG" --id "$SANDBOX_ID" -c \
    "nohup python3 /app/server.py > /tmp/wh.log 2>&1 &" >/dev/null

# Readiness check.
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
    code="$(aca sandbox exec --group "$SG" --id "$SANDBOX_ID" -c \
        "curl -fsS -o /dev/null -w '%{http_code}' -X POST http://localhost:$PORT/healthz || true" \
        2>/dev/null | tail -n1 | tr -d '[:space:]' || true)"
    [[ "$code" == "200" ]] && break
    sleep 1
done
echo "    listener is up"

# ----- 3. Port with entraId.objectIds (gateway MI) -----------------------
echo "==> 3. aca sandbox port add --port $PORT --entra-id-object-ids <gw>"
PORT_CMD=(aca sandbox port add --group "$SG" --id "$SANDBOX_ID" \
          --port "$PORT" --entra-id-object-ids "$GW_PRINCIPAL")
if [[ -n "$USER_EMAIL" && "$USER_EMAIL" == *"@"* ]]; then
    PORT_CMD+=(--email "$USER_EMAIL")
fi
PORT_OUTPUT="$("${PORT_CMD[@]}" -o json)"
PORT_ADDED=1

# Pull URL out of (object or one-element array) JSON via az's JMESPath helper.
# We can't pipe to `az ... --query`; use a temp file + az rest's local JMESPath
# via `--query` if we had it. Fall back to grep for the url field.
PORT_URL="$(echo "$PORT_OUTPUT" \
    | grep -oE '"url"[[:space:]]*:[[:space:]]*"[^"]+"' \
    | head -n1 | sed -E 's/.*"url"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/')"
[[ -n "$PORT_URL" ]] || { echo "error: no URL in port add response" >&2; echo "$PORT_OUTPUT" >&2; exit 1; }
CALLBACK_URL="${PORT_URL%/}/webhook"
echo "    port URL:     $PORT_URL"
echo "    callback URL: $CALLBACK_URL"

# ----- 4. Create trigger config ------------------------------------------
echo "==> 4. PUT trigger config '$CONFIG_NAME'..."
BODY_FILE="$(mktmp)"
cat > "$BODY_FILE" <<EOF
{
  "properties": {
    "connectionDetails": {
      "connectorName": "office365",
      "connectionName": "$CONN"
    },
    "metadata": {
      "sandboxGroupName": "$SG",
      "sandboxId": "$SANDBOX_ID"
    },
    "notificationDetails": {
      "callbackUrl": "$CALLBACK_URL",
      "httpMethod": "Post"
    },
    "operationName": "$OP_NAME",
    "parameters": [
      { "name": "folderPath", "value": "Inbox" }
    ]
  }
}
EOF
STATE="$(az rest --method PUT \
    --url "$ARM_BASE/triggerConfigs/$CONFIG_NAME?api-version=$API_VERSION" \
    --body "@$BODY_FILE" \
    --query "properties.state" -o tsv)"
TRIGGER_CREATED=1
echo "    created (state=${STATE:-?})"

# ----- 5. List, disable, enable ------------------------------------------
echo "==> 5. Listing trigger configs..."
az rest --method GET \
    --url "$ARM_BASE/triggerConfigs?api-version=$API_VERSION" \
    --query "value[].{name:name, state:properties.state}" -o table

echo "==> Disabling the trigger config..."
az rest --method POST \
    --url "$ARM_BASE/triggerConfigs/$CONFIG_NAME/disable?api-version=$API_VERSION" \
    >/dev/null

echo "==> Re-enabling the trigger config..."
az rest --method POST \
    --url "$ARM_BASE/triggerConfigs/$CONFIG_NAME/enable?api-version=$API_VERSION" \
    >/dev/null

echo
echo "==> Lifecycle demo complete."
echo "    Cleaning up: trigger -> port -> sandbox (order matters)."
