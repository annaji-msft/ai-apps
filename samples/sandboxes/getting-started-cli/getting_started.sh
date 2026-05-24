#!/usr/bin/env bash
# Getting Started — Azure Container Apps Sandboxes CLI
#
# End-to-end zero-to-sandbox script. Walks through the full setup:
#   1. az login check
#   2. Create resource group
#   3. Create sandbox group (sets active config)
#   4. Grant yourself the Data Owner role on the sandbox group
#   5. Verify with aca doctor
#   6. Create an Ubuntu sandbox and run a command
#   7. Clean up the sandbox (resource group + sandbox group are kept)
#
# Override defaults via env vars:
#   ACA_RESOURCE_GROUP        (default: aca-samples-rg)
#   ACA_SANDBOX_GROUP         (default: aca-samples-group)
#   ACA_SANDBOXGROUP_REGION   (default: eastus2)

set -euo pipefail

RESOURCE_GROUP="${ACA_RESOURCE_GROUP:-aca-samples-rg}"
SANDBOX_GROUP="${ACA_SANDBOX_GROUP:-aca-samples-group}"
REGION="${ACA_SANDBOXGROUP_REGION:-eastus2}"

# 1. Verify Azure CLI login
echo "==> Checking az login..."
if ! az account show >/dev/null 2>&1; then
    echo "Not logged in. Running 'az login'..."
    az login >/dev/null
fi
SUBSCRIPTION_ID="$(az account show --query id -o tsv)"
PRINCIPAL_ID="$(az ad signed-in-user show --query id -o tsv)"
echo "    subscription: ${SUBSCRIPTION_ID}"
echo "    principal:    ${PRINCIPAL_ID}"

# 2. Create resource group (idempotent)
echo "==> Creating resource group '${RESOURCE_GROUP}' in ${REGION}..."
az group create --name "${RESOURCE_GROUP}" --location "${REGION}" >/dev/null

# 3. Create sandbox group and set as active config
echo "==> Creating sandbox group '${SANDBOX_GROUP}'..."
aca sandboxgroup create \
    --name "${SANDBOX_GROUP}" \
    --location "${REGION}" \
    --resource-group "${RESOURCE_GROUP}" \
    --set-config

# 4. Grant the signed-in user Data Owner role on the sandbox group
echo "==> Assigning 'Container Apps SandboxGroup Data Owner' role..."
aca sandboxgroup role create \
    --role "Container Apps SandboxGroup Data Owner" \
    --principal-id "${PRINCIPAL_ID}" || \
    echo "    (role may already be assigned; continuing)"

# 5. Verify setup
echo "==> Running aca doctor..."
aca doctor

# 6. Create a sandbox and run a command
echo "==> Creating sandbox..."
SANDBOX_ID="$(aca sandbox create --disk ubuntu -o tsv --query id)"
echo "    sandbox: ${SANDBOX_ID}"

cleanup() {
    echo "==> Deleting sandbox ${SANDBOX_ID}..."
    aca sandbox delete --id "${SANDBOX_ID}" --yes >/dev/null || true
}
trap cleanup EXIT

echo "==> Running command in sandbox..."
aca sandbox exec --id "${SANDBOX_ID}" -c "echo hello world && uname -a"

echo "==> Done."
