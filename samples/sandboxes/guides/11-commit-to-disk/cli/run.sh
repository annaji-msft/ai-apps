#!/usr/bin/env bash
set -euo pipefail

dir="$(cd "$(dirname "$0")" && pwd)"
while [[ "$dir" != "/" && ! -f "$dir/.env" ]]; do dir="$(dirname "$dir")"; done
[[ -f "$dir/.env" ]] && { set -a; . "$dir/.env"; set +a; }

DISK="committed-cli-$(date +%s)"
PLABEL="primer-$$"
CLABEL="clone-$$"

cleanup() {
  for L in "$PLABEL" "$CLABEL"; do
    ID=$(aca sandbox list -l "name=$L" -o json 2>/dev/null | python -c "import sys,json;d=json.load(sys.stdin);print(d[0]['id'] if d else '')")
    [[ -n "$ID" ]] && aca sandbox delete --id "$ID" >/dev/null 2>&1 || true
  done
  DID=$(aca sandboxgroup disk list -o json 2>/dev/null | python -c "import sys,json;d=json.load(sys.stdin);print(next((i['id'] for i in d if i.get('labels',{}).get('name')==\"$DISK\"),''))")
  [[ -n "$DID" ]] && aca sandboxgroup disk delete --id "$DID" >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "==> Primer sandbox..."
aca sandbox create --labels "name=$PLABEL" >/dev/null
PID=$(aca sandbox list -l "name=$PLABEL" -o json | python -c "import sys,json;print(json.load(sys.stdin)[0]['id'])")
aca sandbox exec --id "$PID" -c "mkdir -p /opt && echo 'baked-at: \$(date)' > /opt/marker.txt"
echo "    primer wrote /opt/marker.txt"

echo "==> Committing as disk $DISK (5-10 min)..."
aca sandbox commit --id "$PID" --name "$DISK"

echo "==> Deleting primer..."
aca sandbox delete --id "$PID" >/dev/null
sleep 5

echo "==> Boot clone sandbox from $DISK ..."
aca sandbox create --disk "$DISK" --labels "name=$CLABEL" >/dev/null
CID=$(aca sandbox list -l "name=$CLABEL" -o json | python -c "import sys,json;print(json.load(sys.stdin)[0]['id'])")
sleep 8

echo "==> Verify /opt/marker.txt survived..."
aca sandbox exec --id "$CID" -c "cat /opt/marker.txt"
