#!/usr/bin/env bash
# Sandboxes pillar - CLI setup (no Python required).
#
# Provisions:
#   1. Resource group              (az group create)
#   2. aca CLI installed           (official install script)
#   3. CLI config defaults         (aca config set / aca config sandbox set)
#   4. Sandbox group               (aca sandboxgroup create --set-config)
#   5. Data-owner role assignment  (aca sandboxgroup role create)
#   6. samples/.env                (so Python guides can read the same config;
#                                   also captures ACA_USER_EMAIL for the
#                                   Entra-protected scenarios)
#   7. aca doctor                  (verifies everything)
#
# Override defaults with environment variables:
#   AZURE_SUBSCRIPTION_ID      (auto-detected from `az account show`)
#   ACA_RESOURCE_GROUP         default: ai-apps-samples-rg
#   ACA_SANDBOX_GROUP          default: ai-apps-samples-group
#   ACA_SANDBOXGROUP_REGION    default: westus2

set -euo pipefail

ROLE_NAME="Container Apps SandboxGroup Data Owner"
CLI_INSTALL_URL="https://raw.githubusercontent.com/microsoft/azure-container-apps/main/docs/early/aca-cli/install.sh"
CLI_REPO="microsoft/azure-container-apps"
CLI_VERSION_URL="https://raw.githubusercontent.com/${CLI_REPO}/main/docs/early/aca-cli/latest-version.txt"

: "${ACA_RESOURCE_GROUP:=ai-apps-samples-rg}"
: "${ACA_SANDBOX_GROUP:=ai-apps-samples-group}"
: "${ACA_SANDBOXGROUP_REGION:=westus2}"
ACA_REGION="${ACA_REGION:-$ACA_SANDBOXGROUP_REGION}"

# ----- prereq: az login --------------------------------------------------
if ! command -v az >/dev/null 2>&1; then
    echo "error: azure CLI ('az') not found on PATH. Install from https://learn.microsoft.com/cli/azure/install-azure-cli" >&2
    exit 1
fi

SUB="${AZURE_SUBSCRIPTION_ID:-$(az account show --query id -o tsv 2>/dev/null || true)}"
if [[ -z "$SUB" ]]; then
    echo "error: not logged in to Azure. Run 'az login' first." >&2
    exit 1
fi

echo "==> Sandboxes pillar - CLI setup"
echo "    subscription:   $SUB"
echo "    resource group: $ACA_RESOURCE_GROUP"
echo "    sandbox group:  $ACA_SANDBOX_GROUP"
echo "    region:         $ACA_SANDBOXGROUP_REGION"

# ----- 1. Resource group -------------------------------------------------
echo "==> Ensuring resource group '$ACA_RESOURCE_GROUP' in $ACA_SANDBOXGROUP_REGION..."
az group create \
    --subscription "$SUB" \
    --name "$ACA_RESOURCE_GROUP" \
    --location "$ACA_SANDBOXGROUP_REGION" \
    --output none

# ----- 2. Install aca CLI ------------------------------------------------
if ! command -v aca >/dev/null 2>&1; then
    echo "==> Installing the aca CLI..."
    case "$(uname -s)" in
        MINGW*|MSYS*|CYGWIN*)
            # Upstream install.sh rejects Windows uname -s strings; the
            # supported alternative is `irm install.ps1 | iex`, but that
            # pattern is commonly blocked by Defender / ASR. Replicate the
            # PowerShell installer's two-step download-and-extract in plain
            # bash with curl + unzip (both ship with Git Bash). aca.exe ends
            # up in $HOME/.aca/bin — the same path the .ps1 installer uses.
            for tool in curl unzip; do
                if ! command -v $tool >/dev/null 2>&1; then
                    echo "error: detected Windows shell but $tool not found." >&2
                    echo "       Install Git for Windows (which ships both), then re-run." >&2
                    exit 1
                fi
            done
            ACA_VERSION="${ACA_VERSION:-$(curl -fsSL "$CLI_VERSION_URL" | tr -d '[:space:]')}"
            if [[ -z "$ACA_VERSION" ]]; then
                echo "error: could not fetch latest aca CLI version from $CLI_VERSION_URL" >&2
                exit 1
            fi
            ACA_ZIP_URL="https://github.com/${CLI_REPO}/releases/download/${ACA_VERSION}/${ACA_VERSION}-win-x64.zip"
            ACA_TMP="$(mktemp -d)"
            echo "    fetching ${ACA_VERSION} (win-x64)..."
            curl -fsSL "$ACA_ZIP_URL" -o "$ACA_TMP/aca.zip"
            mkdir -p "$HOME/.aca/bin"
            unzip -q -o -j "$ACA_TMP/aca.zip" -d "$HOME/.aca/bin"
            rm -rf "$ACA_TMP"
            ;;
        *)
            curl -fsSL "$CLI_INSTALL_URL" | sh
            ;;
    esac
    export PATH="$HOME/.aca/bin:$PATH"
fi
if ! command -v aca >/dev/null 2>&1; then
    echo "error: 'aca' is still not on PATH after install. Add '$HOME/.aca/bin' to PATH and re-run." >&2
    exit 1
fi
echo "    $(aca --version)"

# ----- 3. CLI shared defaults --------------------------------------------
echo "==> aca config set ... (shared defaults)"
aca config set \
    --subscription "$SUB" \
    --resource-group "$ACA_RESOURCE_GROUP" \
    --region "$ACA_SANDBOXGROUP_REGION" >/dev/null

# ----- 4. Sandbox group --------------------------------------------------
echo "==> Ensuring sandbox group '$ACA_SANDBOX_GROUP'..."
# --set-config saves group + region under the sandbox-specific config block.
# If the group already exists, the command exits non-zero; that's fine.
aca sandboxgroup create \
    --name "$ACA_SANDBOX_GROUP" \
    --location "$ACA_SANDBOXGROUP_REGION" \
    --set-config 2>/dev/null || {
    echo "    sandbox group already exists (saving config explicitly)"
    aca config sandbox set \
        --group "$ACA_SANDBOX_GROUP" \
        --region "$ACA_SANDBOXGROUP_REGION" >/dev/null
}

# ----- 5. RBAC ----------------------------------------------------------
echo "==> Assigning '$ROLE_NAME'..."
# Prefer `az ad signed-in-user` (works for human users with Graph access).
# For service principals or restricted tenants, parse `oid` from the
# management-plane access token instead - same trick the Python flow uses.
PRINCIPAL_ID="$(az ad signed-in-user show --query id -o tsv 2>/dev/null || true)"
USER_EMAIL="$(az account show --query user.name -o tsv 2>/dev/null || true)"
# `az account show` returns the SP appId (not an email) for service principals;
# drop anything that doesn't look like an email so we don't write garbage to .env.
if [[ "$USER_EMAIL" != *"@"* ]]; then
    USER_EMAIL=""
fi
if [[ -z "$PRINCIPAL_ID" ]]; then
    TOKEN="$(az account get-access-token --resource https://management.azure.com/ --query accessToken -o tsv)"
    PAYLOAD="$(printf '%s' "$TOKEN" | cut -d. -f2)"
    # base64url -> base64 + padding
    PAYLOAD="${PAYLOAD//-/+}"
    PAYLOAD="${PAYLOAD//_//}"
    while (( ${#PAYLOAD} % 4 )); do PAYLOAD="${PAYLOAD}="; done
    PRINCIPAL_ID="$(printf '%s' "$PAYLOAD" | base64 -d 2>/dev/null | tr ',{' '\n\n' | grep -oE '"oid":"[^"]+' | head -1 | cut -d'"' -f4 || true)"
fi
if [[ -z "$PRINCIPAL_ID" ]]; then
    echo "    warning: could not determine principal id. Run manually:" >&2
    echo "      aca sandboxgroup role create --role \"$ROLE_NAME\" --principal-id <your-oid>" >&2
else
    aca sandboxgroup role create \
        --role "$ROLE_NAME" \
        --principal-id "$PRINCIPAL_ID" 2>&1 | grep -vE "already|Exists" || true
    echo "    assigned to $PRINCIPAL_ID"
fi
if [[ -z "$USER_EMAIL" ]]; then
    echo "    warning: could not detect a user email (likely a service principal)." >&2
    echo "    Set ACA_USER_EMAIL in samples/.env manually if you want to run the Entra-protected scenarios." >&2
fi

# ----- 6. samples/.env --------------------------------------------------
SAMPLES_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"
ENV_FILE="$SAMPLES_DIR/.env"
echo "==> Writing $ENV_FILE..."

# Read existing keys (preserve anything we don't own).
declare -A EXISTING
if [[ -f "$ENV_FILE" ]]; then
    while IFS='=' read -r k v; do
        # strip whitespace and CR from key
        k="${k//$'\r'/}"
        k="${k%% *}"
        [[ -z "$k" || "${k:0:1}" == "#" ]] && continue
        EXISTING["$k"]="$v"
    done < "$ENV_FILE"
fi
EXISTING[AZURE_SUBSCRIPTION_ID]="$SUB"
EXISTING[ACA_SUBSCRIPTION]="$SUB"
EXISTING[ACA_RESOURCE_GROUP]="$ACA_RESOURCE_GROUP"
EXISTING[ACA_SANDBOX_GROUP]="$ACA_SANDBOX_GROUP"
EXISTING[ACA_SANDBOXGROUP_REGION]="$ACA_SANDBOXGROUP_REGION"
EXISTING[ACA_REGION]="$ACA_REGION"
EXISTING[ACA_USER_EMAIL]="$USER_EMAIL"

{
    echo "# Written by samples/sandboxes/setup/cli/setup.sh"
    echo "# Re-run python or cli setup to update."
    echo ""
    for k in $(printf '%s\n' "${!EXISTING[@]}" | sort); do
        echo "$k=${EXISTING[$k]}"
    done
} > "$ENV_FILE"
echo "    wrote $ENV_FILE"

# ----- 7. Doctor --------------------------------------------------------
echo "==> aca doctor ..."
aca doctor || true

echo "==> Done."
echo "    Next: cd ../../guides/01-sandboxes/cli && ./run.sh"
