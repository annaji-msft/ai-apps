#!/usr/bin/env sh
# Postprovision hook (POSIX shells: bash, zsh, sh).
#
# azd has already created the resource group via infra/main.bicep.
# This hook delegates the rest (preview-API resources + OAuth consent)
# to the SAME imperative setup scripts that the README documents, so the
# azd path and the manual path stay in lock-step.
#
# Order matters:
#   1. samples/sandboxes/setup/python/setup.py        (sandboxes pillar baseline:
#                                                      sandbox group + MI off,
#                                                      Data Owner RBAC, .env)
#   2. samples/sandboxes/scenarios/10-connectors-triggers/setup/python/setup.py
#                                                     (connector gateway + MI,
#                                                      office365 connection,
#                                                      OAuth consent, ACLs,
#                                                      sandbox-group MI on)
#
# Each script is idempotent — safe to re-run after a partial failure.
# Per-run sandbox / trigger lifecycle stays in email-to-sandbox/python/run.py
# (intentionally ephemeral).

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../../../.." && pwd)"
SAMPLES_DIR="$REPO_ROOT/samples"
ENV_FILE="$SAMPLES_DIR/.env"
BASELINE_SETUP="$SAMPLES_DIR/sandboxes/setup/python/setup.py"
BASELINE_REQS="$SAMPLES_DIR/sandboxes/setup/python/requirements.txt"
SCENARIO_SETUP="$SCRIPT_DIR/../../setup/python/setup.py"
SCENARIO_REQS="$SCRIPT_DIR/../../setup/python/requirements.txt"

# 'azd env get-value' writes "ERROR: key not found..." to *stdout* (not
# stderr) and exits non-zero when a key is missing. A naive
# `v=$(azd env get-value KEY 2>/dev/null || true)` captures that error
# string as the value. This helper checks the exit code and prints
# nothing on miss.
azd_get() {
    out="$(azd env get-value "$1" 2>/dev/null)" || return 0
    [ -z "$out" ] && return 0
    printf '%s' "$out"
}

# ----- 0. Preflight: az / aca CLI + auth ----------------------------------
require_tool() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "error: required CLI '$1' not found on PATH. $2" >&2
        exit 1
    fi
}
require_tool az "Install: https://learn.microsoft.com/cli/azure/install-azure-cli"
require_tool aca "Install: https://github.com/microsoft/azure-container-apps/blob/main/docs/early/aca-cli/README.md"

# Resolve python interpreter ONCE (avoid the python3 || python double-run bug).
if command -v python3 >/dev/null 2>&1; then
    PYTHON=python3
elif command -v python >/dev/null 2>&1; then
    PYTHON=python
else
    echo "error: neither python3 nor python found on PATH. Install Python 3.10+." >&2
    exit 1
fi

if ! az account show -o tsv --query id >/dev/null 2>&1; then
    echo "error: az CLI is not logged in. Run 'az login' and re-try 'azd up'." >&2
    exit 1
fi

# ----- 1. Resolve subscription + RG (azd is the source of truth) ----------
SUB="${AZURE_SUBSCRIPTION_ID:-$(azd_get AZURE_SUBSCRIPTION_ID)}"
[ -z "$SUB" ] && SUB="$(az account show --query id -o tsv 2>/dev/null || true)"

ACTIVE_SUB="$(az account show --query id -o tsv 2>/dev/null || true)"
if [ -n "$SUB" ] && [ "$ACTIVE_SUB" != "$SUB" ]; then
    echo "==> Pointing az CLI at subscription $SUB (was $ACTIVE_SUB)"
    az account set --subscription "$SUB"
fi

RG="${ACA_RESOURCE_GROUP:-}"
[ -z "$RG" ] && RG="$(azd_get ACA_RESOURCE_GROUP)"
[ -z "$RG" ] && RG="$(azd_get AZURE_RESOURCE_GROUP)"
if [ -z "$RG" ]; then
    echo "error: could not resolve resource group from azd env." >&2
    exit 1
fi

# Read the RG's actual location and use it as the sandbox-group region.
# This prevents the sandboxes-pillar setup.py from trying to recreate the
# RG in a different region (InvalidResourceGroupLocation). It also means
# the sandbox group ends up in whatever region the user picked at
# 'azd up' time, regardless of the default.
RG_LOCATION="$(az group show --name "$RG" --query location -o tsv 2>/dev/null || true)"
if [ -z "$RG_LOCATION" ]; then
    echo "error: could not read location for resource group '$RG'. Did Bicep deployment succeed?" >&2
    exit 1
fi

# Sandbox groups are only available in a fixed set of regions. Bicep already
# enforces this for the RG via @allowed on the location parameter, but a
# pre-existing RG (created before the @allowed was added, or via a different
# tool) can still slip through here. Fail fast with a clear, actionable
# message so the user doesn't have to read a Python traceback.
SANDBOX_REGIONS="australiaeast brazilsouth canadacentral canadaeast centralus \
eastasia eastus2 francecentral germanywestcentral japaneast koreacentral \
mexicocentral northcentralus northeurope norwayeast polandcentral \
southafricanorth southeastasia southindia spaincentral swedencentral \
switzerlandnorth uksouth westcentralus westus westus2 westus3"
RG_LOCATION_LOWER="$(echo "$RG_LOCATION" | tr '[:upper:]' '[:lower:]')"
case " $SANDBOX_REGIONS " in
    *" $RG_LOCATION_LOWER "*) ;;
    *)
        cat >&2 <<EOF
error: Resource group '$RG' is in region '$RG_LOCATION', which does not
support Microsoft.App/sandboxGroups.

Supported regions:
  $SANDBOX_REGIONS

To recover:
  1. azd down --purge             # removes the bad RG
  2. azd env set AZURE_LOCATION westus2
  3. azd up                       # provisions in a supported region
EOF
        exit 1
        ;;
esac

export ACA_SANDBOXGROUP_REGION="$RG_LOCATION"
export ACA_REGION="$RG_LOCATION"
echo "==> Using RG location '$RG_LOCATION' as sandbox-group region (override with ACA_SANDBOXGROUP_REGION + azd up to change)."

# ----- 2. Interactivity preflight (OAuth needs a TTY) ---------------------
if [ ! -t 0 ]; then
    echo "==> stdin appears to be redirected; OAuth consent flow may fail." >&2
    echo "    If setup.py prompts and exits, re-run 'azd up' from an interactive shell." >&2
fi

echo "==> azd postprovision: provisioning preview-API resources"
echo "    subscription:    $SUB"
echo "    resource group:  $RG"
echo "    (Bicep created only the RG; everything else uses preview APIs"
echo "     for which Bicep types are not yet published.)"
echo

# ----- 3. Seed samples/.env so setup.py finds subscription + RG -----------
set_env_line() {
    # $1=path  $2=key  $3=value
    [ -z "$3" ] && return 0
    if [ ! -f "$1" ]; then
        printf '# Seeded by azd postprovision\n%s=%s\n' "$2" "$3" > "$1"
        return 0
    fi
    if grep -q "^${2}=" "$1" 2>/dev/null; then
        tmp="$1.tmp.$$"
        awk -v k="$2" -v v="$3" '
            BEGIN { sub_re = "^" k "=" }
            $0 ~ sub_re { print k "=" v; next }
            { print }
        ' "$1" > "$tmp"
        mv "$tmp" "$1"
    else
        printf '%s=%s\n' "$2" "$3" >> "$1"
    fi
}

if [ ! -f "$ENV_FILE" ]; then
    echo "    creating $ENV_FILE"
    mkdir -p "$(dirname "$ENV_FILE")"
    : > "$ENV_FILE"
fi

set_env_line "$ENV_FILE" "AZURE_SUBSCRIPTION_ID" "$SUB"
set_env_line "$ENV_FILE" "ACA_SUBSCRIPTION" "$SUB"
set_env_line "$ENV_FILE" "ACA_RESOURCE_GROUP" "$RG"
set_env_line "$ENV_FILE" "ACA_SANDBOXGROUP_REGION" "$RG_LOCATION"
set_env_line "$ENV_FILE" "ACA_REGION" "$RG_LOCATION"

# Mirror any user-set azd overrides through to the setup.py child process
# as plain env vars (do NOT write them into samples/.env — setup.py is the
# source of truth for those keys and writes them back to samples/.env on
# success). Matches the sandbox-group pattern: setup.py reads defaults
# from its own environment.
for k in \
    ACA_SANDBOX_GROUP \
    ACA_CONNECTOR_GATEWAY \
    ACA_CONNECTOR_GATEWAY_REGION \
    ACA_CONNECTOR_CONNECTION \
    ACA_USER_EMAIL
do
    v="$(azd_get "$k")"
    [ -n "$v" ] && export "$k=$v"
done

# ----- 4. Sandboxes-pillar baseline (sandbox group + MI + Data Owner) -----
echo "==> [1/2] Sandboxes-pillar baseline (sandbox group + RBAC)..."
"$PYTHON" -m pip install --quiet --disable-pip-version-check -r "$BASELINE_REQS"
"$PYTHON" "$BASELINE_SETUP"

# ----- 5. Connector-trigger scenario setup (gateway + connection + OAuth)
echo
echo "==> [2/2] Connector-gateway scenario setup (gateway + connection + OAuth consent)..."
"$PYTHON" -m pip install --quiet --disable-pip-version-check -r "$SCENARIO_REQS"
"$PYTHON" "$SCENARIO_SETUP"

# ----- 6. Mirror samples/.env -> azd env ----------------------------------
echo
echo "==> Mirroring connector keys into azd env..."
MIRROR="ACA_SANDBOX_GROUP ACA_SANDBOX_GROUP_PRINCIPAL_ID ACA_SANDBOXGROUP_REGION ACA_REGION ACA_CONNECTOR_GATEWAY ACA_CONNECTOR_GATEWAY_REGION ACA_CONNECTOR_GATEWAY_PRINCIPAL_ID ACA_CONNECTOR_GATEWAY_TENANT_ID ACA_CONNECTOR_CONNECTION ACA_CONNECTOR_CONNECTION_RUNTIME_URL ACA_USER_EMAIL"
while IFS= read -r line; do
    case "$line" in
        ''|\#*) continue ;;
    esac
    key="${line%%=*}"
    val="${line#*=}"
    if [ -z "$key" ] || [ "$key" = "$line" ]; then continue; fi
    for m in $MIRROR; do
        if [ "$key" = "$m" ] && [ -n "$val" ]; then
            azd env set "$key" "$val" >/dev/null
            break
        fi
    done
done < "$ENV_FILE"

echo
echo "==> azd postprovision: done."
echo
echo "Next, fire the end-to-end demo with:"
echo "  cd email-to-sandbox/python && pip install -r requirements.txt && python run.py"
echo "or:"
echo "  bash email-to-sandbox/cli/run.sh"
