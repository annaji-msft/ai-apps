#!/usr/bin/env bash
# Sandboxes pillar - CLI teardown.
# Deletes the sandbox group, then the resource group. No Python required.

set -euo pipefail

# Load samples/.env so we know what to delete.
SAMPLES_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"
ENV_FILE="$SAMPLES_DIR/.env"
if [[ -f "$ENV_FILE" ]]; then
    set -a
    # shellcheck disable=SC1090
    . "$ENV_FILE"
    set +a
fi

YES=0
[[ "${1:-}" == "--yes" ]] && YES=1

SUB="${AZURE_SUBSCRIPTION_ID:-$(az account show --query id -o tsv 2>/dev/null || true)}"
: "${ACA_RESOURCE_GROUP:?ACA_RESOURCE_GROUP not set - run setup.sh first?}"
: "${ACA_SANDBOX_GROUP:?ACA_SANDBOX_GROUP not set - run setup.sh first?}"

echo "This will delete:"
echo "  sandbox group:  $ACA_SANDBOX_GROUP"
echo "  resource group: $ACA_RESOURCE_GROUP (and ALL resources in it)"
if (( ! YES )); then
    read -r -p "Continue? [y/N] " reply
    case "$reply" in
        y|Y|yes|YES) ;;
        *) echo "aborted."; exit 0 ;;
    esac
fi

echo "==> Deleting sandbox group '$ACA_SANDBOX_GROUP'..."
aca sandboxgroup delete --name "$ACA_SANDBOX_GROUP" --yes 2>/dev/null || true

echo "==> Deleting resource group '$ACA_RESOURCE_GROUP' (background)..."
az group delete --subscription "$SUB" --name "$ACA_RESOURCE_GROUP" --yes --no-wait

echo "==> Done. (Resource group deletion runs in the background.)"
