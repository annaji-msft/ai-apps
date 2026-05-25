#!/usr/bin/env bash
set -euo pipefail

dir="$(cd "$(dirname "$0")" && pwd)"
while [[ "$dir" != "/" && ! -f "$dir/.env" ]]; do dir="$(dirname "$dir")"; done
[[ -f "$dir/.env" ]] && { set -a; . "$dir/.env"; set +a; }

DISK="alpine-cli-$(date +%s)"
SLABEL="cdisk-cli-$$"

cleanup() {
  SID=$(aca sandbox list -l "name=$SLABEL" -o json 2>/dev/null | python -c "import sys,json;d=json.load(sys.stdin);print(d[0]['id'] if d else '')")
  [[ -n "$SID" ]] && aca sandbox delete --id "$SID" >/dev/null 2>&1 || true
  DID=$(aca sandboxgroup disk list -o json 2>/dev/null | python -c "import sys,json;d=json.load(sys.stdin);print(next((i['id'] for i in d if i.get('labels',{}).get('name')==\"$DISK\"),''))")
  [[ -n "$DID" ]] && aca sandboxgroup disk delete --id "$DID" >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "==> Building disk image $DISK from alpine:3.19 (5-10 min)..."
aca sandboxgroup disk create --image docker.io/library/alpine:3.19 --name "$DISK"

echo "==> Listing disks:"
aca sandboxgroup disk list

echo "==> Boot sandbox from $DISK ..."
aca sandbox create --disk "$DISK" --labels "name=$SLABEL" >/dev/null
SID=$(aca sandbox list -l "name=$SLABEL" -o json | python -c "import sys,json;print(json.load(sys.stdin)[0]['id'])")
echo "    sandbox: $SID"

echo "==> cat /etc/alpine-release ..."
aca sandbox exec --id "$SID" -c "cat /etc/alpine-release"
