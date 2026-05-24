#!/usr/bin/env bash
# Hello World sample for the Azure Container Apps Sandboxes CLI.
#
# Creates an Ubuntu sandbox, runs a command, prints the output, and deletes
# the sandbox. Requires an active sandbox-group config (see README.md).

set -euo pipefail

echo "Creating sandbox..."
SANDBOX_ID="$(aca sandbox create --disk ubuntu -o tsv --query id)"
echo "Created sandbox: ${SANDBOX_ID}"

cleanup() {
    aca sandbox delete --id "${SANDBOX_ID}" --yes >/dev/null
    echo "Deleted sandbox ${SANDBOX_ID}."
}
trap cleanup EXIT

aca sandbox exec --id "${SANDBOX_ID}" -c "echo hello world && uname -a"
