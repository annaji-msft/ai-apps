#!/usr/bin/env bash
# Custom disk image - build from a public container image and boot from it.
#
# Demonstrates the create / list / get convention on disk images, then
# boots a sandbox from the custom disk and verifies it's Alpine.

set -euo pipefail

dir="$(cd "$(dirname "$0")" && pwd)"
while [[ "$dir" != "/" && ! -f "$dir/.env" ]]; do dir="$(dirname "$dir")"; done
[[ -f "$dir/.env" ]] && { set -a; . "$dir/.env"; set +a; }

DISK="alpine-cli-$(date +%s)"
DID=""
SID=""

cleanup() {
    if [[ -n "$SID" ]]; then
        echo "==> Deleting sandbox $SID..."
        aca sandbox delete --id "$SID" --yes >/dev/null 2>&1 || true
    fi
    if [[ -n "$DID" ]]; then
        echo "==> Deleting disk image $DID..."
        aca sandboxgroup disk delete --id "$DID" --yes >/dev/null 2>&1 || true
    fi
}
trap cleanup EXIT

echo "==> Public disk images (use these names as --disk values):"
aca sandboxgroup disk list-public

echo "==> Building disk image '$DISK' from alpine:3.19 (5-10 min)..."
CREATE_OUTPUT="$(aca sandboxgroup disk create --image docker.io/library/alpine:3.19 --name "$DISK")"
echo "$CREATE_OUTPUT"
# `disk create` returns JSON; the first "id" field is the disk image id.
DID="$(echo "$CREATE_OUTPUT" | sed -n 's/.*"id": *"\([^"]*\)".*/\1/p' | head -n1)"
if [[ -z "$DID" ]]; then
    echo "error: could not parse disk image id from create output" >&2
    exit 1
fi

echo "==> Listing your private disk images:"
aca sandboxgroup disk list

echo "==> Get details for '$DISK':"
aca sandboxgroup disk get --id "$DID"

# Private/custom disks must be referenced by --disk-id; --disk is for
# public images only (see `aca sandboxgroup disk list-public`).
echo "==> Booting sandbox from disk-id $DID..."
CREATE_OUTPUT="$(aca sandbox create --disk-id "$DID")"
echo "$CREATE_OUTPUT"
SID="$(echo "$CREATE_OUTPUT" | sed -n 's/^Created sandbox: //p' | tail -n1)"
if [[ -z "$SID" ]]; then
    echo "error: could not parse sandbox id from create output" >&2
    exit 1
fi

echo "==> Verifying - should be Alpine:"
aca sandbox exec --id "$SID" -c "cat /etc/alpine-release"
