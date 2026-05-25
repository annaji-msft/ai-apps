#!/usr/bin/env bash
# Getting started - create a sandbox, run a command, delete it (aca CLI).
#
# Reads samples/.env (written by samples/sandboxes/setup/setup.py) for
# ACA_SUBSCRIPTION, ACA_RESOURCE_GROUP, ACA_SANDBOX_GROUP.

set -euo pipefail

# Walk up from this script to find samples/.env.
dir="$(cd "$(dirname "$0")" && pwd)"
while [[ "$dir" != "/" && ! -f "$dir/.env" ]]; do
    dir="$(dirname "$dir")"
done
if [[ -f "$dir/.env" ]]; then
    set -a
    # shellcheck disable=SC1091
    . "$dir/.env"
    set +a
else
    echo "error: could not find samples/.env - run setup/setup.py first?" >&2
    exit 1
fi

echo "==> Creating sandbox..."
CREATE_OUTPUT="$(aca sandbox create --disk ubuntu)"
echo "$CREATE_OUTPUT"
SANDBOX_ID="$(echo "$CREATE_OUTPUT" | sed -n 's/^Created sandbox: //p' | tail -n1)"
if [[ -z "$SANDBOX_ID" ]]; then
    echo "error: could not parse sandbox id from create output" >&2
    exit 1
fi

cleanup() {
    echo "==> Deleting sandbox $SANDBOX_ID..."
    aca sandbox delete --id "$SANDBOX_ID" --yes >/dev/null || true
}
trap cleanup EXIT

echo "==> Running command in sandbox..."
aca sandbox exec --id "$SANDBOX_ID" -c "echo hello world && uname -a"

echo "==> Done."
