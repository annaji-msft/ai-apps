#!/usr/bin/env bash
# Web app in a sandbox - Entra ID protected public port (aca CLI).
#
# Same flow as run_anonymous.sh but `port add --email "$ACA_USER_EMAIL"` gates
# the public URL. Verification proves the gate by hitting the URL with no auth
# and asserting a non-2xx response.

set -euo pipefail

# git-bash on Windows rewrites absolute POSIX paths (like `/app/server.js`) into
# Windows paths before passing them to non-POSIX binaries. Suppress that so the
# `--path /app/...` arguments to `aca` reach the sandbox unchanged.
export MSYS_NO_PATHCONV=1
export MSYS2_ARG_CONV_EXCL='*'

here="$(cd "$(dirname "$0")" && pwd)"
dir="$here"
while [[ "$dir" != "/" && ! -f "$dir/.env" ]]; do
    dir="$(dirname "$dir")"
done
if [[ -f "$dir/.env" ]]; then
    set -a; . "$dir/.env"; set +a
else
    echo "error: could not find samples/.env - run setup/cli/setup.sh first?" >&2
    exit 1
fi

DISK="${ACA_WEBAPP_DISK:-node-22}"
PORT=8080
APP_DIR="$here/../app"
EMAIL="${ACA_USER_EMAIL:-}"

# Convert a path for the aca CLI. On Windows + git-bash, `aca.exe` expects a
# native Windows path (cygpath -w). Elsewhere, pass through.
to_native() {
    if command -v cygpath >/dev/null 2>&1; then cygpath -w "$1"; else echo "$1"; fi
}

# Extract a top-level string field from a JSON blob on stdin. The blob may be
# an object or a one-element array (aca CLI returns arrays for some commands).
# No hard dependency on jq or python3.
json_field() {
    local field="$1"
    if command -v jq >/dev/null 2>&1; then
        jq -r "if type==\"array\" then .[0].${field} else .${field} end // empty"
    elif command -v python3 >/dev/null 2>&1; then
        python3 -c "import sys,json; d=json.load(sys.stdin); d=d[0] if isinstance(d,list) else d; print(d.get('${field}',''))"
    elif command -v python >/dev/null 2>&1; then
        python -c "import sys,json; d=json.load(sys.stdin); d=d[0] if isinstance(d,list) else d; print(d.get('${field}',''))"
    else
        sed -n 's/.*"'"$field"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1
    fi
}

if [[ -z "$EMAIL" ]]; then
    echo "error: ACA_USER_EMAIL is empty in samples/.env. This scenario gates" >&2
    echo "       the public port to a specific Entra ID user. Re-run setup as" >&2
    echo "       a human user, or set ACA_USER_EMAIL manually in samples/.env." >&2
    exit 1
fi

echo "==> Creating sandbox (disk=$DISK)..."
CREATE_OUTPUT="$(aca sandbox create --disk "$DISK")"
SANDBOX_ID="$(echo "$CREATE_OUTPUT" | sed -n 's/^Created sandbox: //p' | tail -n1)"
[[ -n "$SANDBOX_ID" ]] || { echo "error: could not parse sandbox id" >&2; exit 1; }
echo "    sandbox: $SANDBOX_ID"

PORT_ADDED=0
cleanup() {
    if [[ "$PORT_ADDED" == "1" ]]; then
        echo "==> aca sandbox port remove --port $PORT"
        aca sandbox port remove --id "$SANDBOX_ID" --port "$PORT" >/dev/null 2>&1 || \
          echo "    warning: port remove failed"
    fi
    echo "==> Deleting sandbox $SANDBOX_ID..."
    aca sandbox delete --id "$SANDBOX_ID" --yes >/dev/null || true
}
trap cleanup EXIT

echo "==> Uploading app files..."
aca sandbox exec --id "$SANDBOX_ID" -c "mkdir -p /app" >/dev/null
aca sandbox fs write --id "$SANDBOX_ID" --path /app/server.js   --file "$(to_native "$APP_DIR/server.js")"   >/dev/null
aca sandbox fs write --id "$SANDBOX_ID" --path /app/package.json --file "$(to_native "$APP_DIR/package.json")" >/dev/null

echo "==> Starting Node server on :$PORT..."
aca sandbox exec --id "$SANDBOX_ID" -c \
  "cd /app && nohup node server.js > /tmp/node.log 2>&1 &" >/dev/null

echo "==> Polling in-sandbox readiness on /healthz..."
for i in $(seq 1 30); do
    code="$(aca sandbox exec --id "$SANDBOX_ID" -c \
      "curl -fsS -o /dev/null -w '%{http_code}' http://localhost:$PORT/healthz || true" 2>/dev/null | tail -n1 | tr -d '[:space:]')"
    if [[ "$code" == "200" ]]; then break; fi
    sleep 1
done
if [[ "$code" != "200" ]]; then
    echo "error: server not ready (last code=$code)" >&2
    aca sandbox exec --id "$SANDBOX_ID" -c "cat /tmp/node.log" >&2 || true
    exit 1
fi
echo "    server is ready"

echo "==> In-sandbox JSON shape checks..."
for path in "/" "/healthz" "/api/info"; do
    body="$(aca sandbox exec --id "$SANDBOX_ID" -c "curl -fsS http://localhost:$PORT$path" 2>/dev/null | tail -n+1)"
    echo "    GET $path -> $body"
done

echo "==> aca sandbox port add --port $PORT --email $EMAIL"
PORT_OUTPUT="$(aca sandbox port add --id "$SANDBOX_ID" --port "$PORT" --email "$EMAIL" -o json)"
PORT_ADDED=1
URL="$(echo "$PORT_OUTPUT" | json_field url)"
[[ -n "$URL" ]] || { echo "error: no URL in port add response" >&2; exit 1; }
echo "    public URL: $URL"

echo "==> Verifying the Entra ID gate (host-side, NO auth)..."
deadline=$(( $(date +%s) + 60 ))
status=0
while :; do
    status="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$URL/healthz" 2>/dev/null || true)"
    status="${status//[!0-9]/}"
    [[ -z "$status" ]] && status=0
    if [[ "$status" =~ ^(401|403|302)$ ]]; then break; fi
    [[ $(date +%s) -lt $deadline ]] || break
    sleep 2
done
if [[ "$status" == "200" ]]; then
    echo "error: expected non-2xx for unauthenticated request, got $status" >&2
    echo "       is --email actually being honored?" >&2
    exit 1
fi
echo "    anonymous GET -> http $status (gate is working)"

echo
echo "==> Done. To reach the app interactively:"
echo "    open $URL"
echo "    and sign in as $EMAIL"
