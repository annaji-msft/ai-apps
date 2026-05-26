#!/usr/bin/env bash
# MI inception swarm — aca CLI variant.
#
# Story: a sandbox in orchestrator group A uses its group's
# system-assigned managed identity to create and drive N worker
# sandboxes in a separate group B — no credential is ever placed
# inside the agent. Demonstration task: Monte Carlo Pi across the
# workers, aggregated by the orchestrator.
#
# The script is built so `aca config` is the obvious win — neither the
# host nor the orchestrator carries `--subscription / --resource-group /
# --group / --managed-identity` flags on individual `aca` calls.
#
# Reads samples/.env (written by setup/python/setup.py or
# setup/cli/setup.sh).

set -euo pipefail

# ---------------- 0. Source samples/.env ----------------
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
    echo "error: could not find samples/.env — run setup/cli/setup.sh first" >&2
    exit 1
fi

ROLE_NAME="Container Apps SandboxGroup Data Owner"
CLI_INSTALL_URL="https://raw.githubusercontent.com/microsoft/azure-container-apps/main/docs/early/aca-cli/install.sh"
WORKERS=4
DARTS_PER_WORKER=1000000
SUFFIX="$(uuidgen 2>/dev/null | tr -d - | head -c6 || printf '%06x' $RANDOM$RANDOM)"
ORCH_GROUP="swarm-orch-$SUFFIX"
WORKER_GROUP="swarm-workers-$SUFFIX"
ORIGINAL_SANDBOX_GROUP="${ACA_SANDBOX_GROUP:-}"
ORCH_ID=""

cleanup() {
    set +e
    if [[ -n "$ORCH_ID" ]]; then
        echo "==> Deleting orchestrator sandbox $ORCH_ID..."
        aca --group "$ORCH_GROUP" sandbox delete --id "$ORCH_ID" --yes >/dev/null 2>&1
    fi
    for grp in "$ORCH_GROUP" "$WORKER_GROUP"; do
        echo "==> Deleting sandbox group $grp..."
        aca sandboxgroup delete --name "$grp" --yes >/dev/null 2>&1
    done
    if [[ -n "$ORIGINAL_SANDBOX_GROUP" ]]; then
        echo "==> Restoring original aca config sandbox group ($ORIGINAL_SANDBOX_GROUP)..."
        aca config sandbox set --group "$ORIGINAL_SANDBOX_GROUP" >/dev/null 2>&1
    fi
}
trap cleanup EXIT

# ---------------- 1. Provision orchestrator group with MI ----------------
echo "==> Provisioning orchestrator group $ORCH_GROUP with SystemAssigned MI..."
# --set-config flips the current sandbox context to this group, so every
# subsequent `aca sandboxgroup` / `aca sandbox` call targets it without
# needing --group on each line. This is the aca config showcase.
aca sandboxgroup create \
    --name "$ORCH_GROUP" \
    --location "$ACA_SANDBOXGROUP_REGION" \
    --set-config >/dev/null

aca sandboxgroup identity assign --name "$ORCH_GROUP" --system-assigned >/dev/null

PRINCIPAL_ID="$(aca sandboxgroup identity show --name "$ORCH_GROUP" -o json \
    | python3 -c 'import json,sys; print(json.load(sys.stdin).get("principalId",""))')"
if [[ -z "$PRINCIPAL_ID" ]]; then
    echo "error: orchestrator group has no principalId — MI not enabled?" >&2
    exit 1
fi
echo "    principalId: $PRINCIPAL_ID"

echo "==> Host config (orchestrator context):"
aca config show

# ---------------- 2. Worker group + role grant ----------------
echo "==> Provisioning worker group $WORKER_GROUP..."
aca sandboxgroup create \
    --name "$WORKER_GROUP" \
    --location "$ACA_SANDBOXGROUP_REGION" >/dev/null

echo "==> Granting '$ROLE_NAME' on $WORKER_GROUP → orchestrator MI..."
aca sandboxgroup role create \
    --role "$ROLE_NAME" \
    --principal-id "$PRINCIPAL_ID" \
    --name "$WORKER_GROUP" 2>&1 | grep -vE "already|Exists" || true

echo "==> Waiting 20s for RBAC propagation..."
sleep 20

# ---------------- 3. Orchestrator sandbox ----------------
echo "==> Creating orchestrator sandbox (disk=ubuntu) in $ORCH_GROUP..."
CREATE_OUT="$(aca sandbox create --disk ubuntu --label swarm=mi-inception --label role=orchestrator)"
echo "$CREATE_OUT"
ORCH_ID="$(printf '%s\n' "$CREATE_OUT" | sed -n 's/^Created sandbox: //p' | tail -n1)"
if [[ -z "$ORCH_ID" ]]; then
    echo "error: could not parse orchestrator sandbox id" >&2
    exit 1
fi

# ---------------- 4. Bootstrap orchestrator (install aca + upload swarm.sh) ----------------
echo "==> Installing aca CLI inside orchestrator..."
aca sandbox exec --id "$ORCH_ID" -c "curl -fsSL $CLI_INSTALL_URL | sh" >/dev/null

SWARM_SH="$(mktemp)"
cat > "$SWARM_SH" <<'INNER_EOF'
#!/usr/bin/env bash
# Runs INSIDE the orchestrator sandbox. Uses the group's MI (via
# ACA_SANDBOX_MANAGED_IDENTITY=system) to fan out N worker sandbox
# creates + execs in the WORKER group — same `aca` binary, but the
# context env vars point at the worker group rather than the
# orchestrator group. The block below is the aca config showcase: every
# `aca` call below is parameter-free because the context is already set.

set -uo pipefail
ACA="$HOME/.aca/bin/aca"

echo "--- aca auth status (orchestrator, MI) ---"
"$ACA" auth status || true

echo "--- env-based config (worker context) ---"
echo "ACA_SUBSCRIPTION=$ACA_SUBSCRIPTION"
echo "ACA_RESOURCE_GROUP=$ACA_RESOURCE_GROUP"
echo "ACA_SANDBOX_GROUP=$ACA_SANDBOX_GROUP"
echo "ACA_SANDBOX_MANAGED_IDENTITY=$ACA_SANDBOX_MANAGED_IDENTITY"
echo "ACA_REGION=$ACA_REGION"

PI_SNIPPET="python3 -c 'import random as r, sys; n=int(sys.argv[1]); inside=sum(1 for _ in range(n) if r.random()**2 + r.random()**2 < 1.0); print(f\"INSIDE={inside} TOTAL={n}\")' $DARTS"

worker_run() {
    local i="$1"
    local out="/tmp/worker_${i}.out"
    local t0 t1 dt id create_out exec_out
    t0=$(date +%s.%N)
    create_out="$("$ACA" sandbox create --disk ubuntu --label worker=$i 2>&1)"
    id="$(printf '%s\n' "$create_out" | sed -n 's/^Created sandbox: //p' | tail -n1)"
    if [[ -z "$id" ]]; then
        echo "WORKER_ERROR $i create_failed" > "$out"
        return
    fi
    exec_out="$("$ACA" sandbox exec --id "$id" -c "$PI_SNIPPET" 2>&1)"
    t1=$(date +%s.%N)
    dt=$(awk "BEGIN{printf \"%.2f\", $t1 - $t0}")
    inside="$(printf '%s\n' "$exec_out" | grep -oE 'INSIDE=[0-9]+' | head -1 | cut -d= -f2)"
    total="$(printf '%s\n' "$exec_out" | grep -oE 'TOTAL=[0-9]+'  | head -1 | cut -d= -f2)"
    echo "WORKER_RESULT $i $id INSIDE=${inside:-0} TOTAL=${total:-0} ELAPSED_S=$dt" > "$out"
    "$ACA" sandbox delete --id "$id" --yes >/dev/null 2>&1 || true
}

echo "--- spawning $WORKERS workers in $ACA_SANDBOX_GROUP via MI ---"
for i in $(seq 0 $((WORKERS-1))); do
    worker_run "$i" &
done
wait

for i in $(seq 0 $((WORKERS-1))); do
    cat "/tmp/worker_${i}.out"
done
INNER_EOF

echo "==> Uploading swarm.sh into orchestrator..."
aca sandbox fs write --id "$ORCH_ID" --path /tmp/swarm.sh --file "$SWARM_SH"
rm -f "$SWARM_SH"

# ---------------- 5. Run swarm inside orchestrator ----------------
echo "==> Orchestrator: spawning $WORKERS workers in $WORKER_GROUP via MI..."
ENV_LINE="ACA_SUBSCRIPTION=$ACA_SUBSCRIPTION ACA_RESOURCE_GROUP=$ACA_RESOURCE_GROUP \
ACA_SANDBOX_GROUP=$WORKER_GROUP ACA_SANDBOX_MANAGED_IDENTITY=system \
ACA_REGION=$ACA_SANDBOXGROUP_REGION WORKERS=$WORKERS DARTS=$DARTS_PER_WORKER"

SWARM_OUTPUT="$(aca sandbox exec --id "$ORCH_ID" -c "$ENV_LINE bash /tmp/swarm.sh")"
echo "$SWARM_OUTPUT"

# ---------------- 6. Aggregate Pi on the host ----------------
echo "==> Aggregating across $((WORKERS * DARTS_PER_WORKER)) darts..."
TOTAL_INSIDE=0
TOTAL_DARTS=0
while read -r line; do
    if [[ "$line" =~ INSIDE=([0-9]+)\ TOTAL=([0-9]+) ]]; then
        TOTAL_INSIDE=$((TOTAL_INSIDE + ${BASH_REMATCH[1]}))
        TOTAL_DARTS=$((TOTAL_DARTS + ${BASH_REMATCH[2]}))
    fi
done <<< "$SWARM_OUTPUT"

if [[ "$TOTAL_DARTS" -eq 0 ]]; then
    echo "error: no worker results parsed — see output above" >&2
    exit 1
fi
PI=$(awk "BEGIN{pi=4*$TOTAL_INSIDE/$TOTAL_DARTS; err=pi-3.141592653589793; if(err<0)err=-err; printf \"pi ≈ %.6f  (error %.2e)\", pi, err}")
echo "    $PI"

echo "==> Done."
