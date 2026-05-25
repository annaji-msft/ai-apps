#!/usr/bin/env bash
# Web app deployment - run a Node.js HTTP server in a sandbox, expose it (aca CLI).

set -euo pipefail

dir="$(cd "$(dirname "$0")" && pwd)"
while [[ "$dir" != "/" && ! -f "$dir/.env" ]]; do
    dir="$(dirname "$dir")"
done
if [[ -f "$dir/.env" ]]; then
    set -a; . "$dir/.env"; set +a
else
    echo "error: could not find samples/.env - run setup/setup.py first?" >&2
    exit 1
fi

SANDBOX_ID=""
APP_FILE=/tmp/aca-sample-index.js

cleanup() {
    if [[ -n "$SANDBOX_ID" ]]; then
        echo "==> Deleting sandbox $SANDBOX_ID..."
        aca sandbox delete --id "$SANDBOX_ID" --yes >/dev/null 2>&1 || true
    fi
    rm -f "$APP_FILE"
}
trap cleanup EXIT

cat > "$APP_FILE" <<'JS'
const http = require('http');
const os = require('os');
http.createServer((req, res) => {
  res.writeHead(200, {'Content-Type': 'application/json'});
  res.end(JSON.stringify({
    message: 'Hello from sandbox!',
    hostname: os.hostname(),
    uptime: process.uptime(),
    path: req.url,
  }, null, 2));
}).listen(8080, '0.0.0.0', () => console.log('Server on :8080'));
JS

echo "==> Booting sandbox from 'node-22' disk image..."
SANDBOX_ID="$(aca sandbox create --disk node-22 | sed -n 's/^Created sandbox: //p' | tail -n1)"
echo "    sandbox: $SANDBOX_ID"
sleep 10

echo "==> Uploading /app/index.js..."
aca sandbox fs mkdir --id "$SANDBOX_ID" --path /app 2>/dev/null || true
aca sandbox fs write --id "$SANDBOX_ID" --path /app/index.js --file "$APP_FILE"

echo "==> Starting server (nohup node /app/index.js)..."
aca sandbox exec --id "$SANDBOX_ID" -c "cd /app && nohup node index.js > /tmp/node.log 2>&1 &"
sleep 3

echo "    in-sandbox curl:"
aca sandbox exec --id "$SANDBOX_ID" -c "curl -s http://localhost:8080 || cat /tmp/node.log"

echo "==> Publishing port 8080..."
URL="$(aca sandbox port add --id "$SANDBOX_ID" --port 8080 --anonymous -o json | python3 -c "import sys,json; print(json.load(sys.stdin).get('url',''))")"
echo "    public URL: $URL"
[[ -n "$URL" ]] || { echo "error: no URL in add port response" >&2; exit 1; }

echo "==> Hitting public URL from this machine..."
sleep 8
curl -s --max-time 15 "$URL"
echo

echo "==> Done."
