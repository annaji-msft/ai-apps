# Connector-gateway scenario - setup

The connector-trigger samples need a small one-time Azure baseline:

1. The **sandboxes pillar baseline** (resource group + sandbox group + RBAC).
   This scenario reuses it. Run `samples/sandboxes/setup/python/setup.py`
   **or** `samples/sandboxes/setup/cli/setup.sh` first.
2. A **connector gateway** with a system-assigned managed identity, in the
   same resource group as the sandbox group.
3. An **Office 365 connection** on that gateway, OAuth-authorized to your
   inbox. (You'll click a consent link once.)
4. Two **access policies**: one for the gateway MI (lets it subscribe to
   events) and one for the sandbox-group MI (lets sandboxes call the
   connection runtime URL).
5. A **`gatewayConnections[]` entry on the sandbox group** wiring the
   connection's `connectionRuntimeUrl` to `SystemAssignedManagedIdentity`.
   When per-sandbox `gatewayConnections=[{ resourceId }]` is also set at
   create-time (see `email-to-sandbox/run.py`), the platform proxy
   injects the Bearer token automatically — no per-sandbox egress
   Transform rule needed.
6. New keys appended to `samples/.env` so the sub-scenarios in this folder
   can find the gateway and connection.

Pick the flow that matches the surface you want to use:

| Flow | Folder | When to use |
|------|--------|-------------|
| **azd** | [`../`](..) — `azd up` at the scenario root | One-command provisioning. Wraps the two manual setup steps below into `azd up`; `azd down` cleans up the whole resource group. |
| **Python** | [`python/`](./python/) | You'll mostly run the Python sub-scenarios. Needs Python 3.10+ + pip. |
| **CLI**    | [`cli/`](./cli/)       | You'll mostly run the CLI sub-scenarios. **No Python required** — bash on Linux, macOS, or Windows (Git Bash / WSL / MSYS2). |

Both flows write the same keys to `samples/.env`:

| Key | What it is | Default |
|---|---|---|
| `ACA_CONNECTOR_GATEWAY` | Gateway resource name | `ai-apps-samples-gw` |
| `ACA_CONNECTOR_GATEWAY_REGION` | Gateway region | `ACA_SANDBOXGROUP_REGION` |
| `ACA_CONNECTOR_CONNECTION` | Office 365 connection name | `o365-conn` |
| `ACA_CONNECTOR_GATEWAY_PRINCIPAL_ID` | Gateway MI principal id (oid) | _auto_ |
| `ACA_CONNECTOR_GATEWAY_TENANT_ID` | Gateway MI tenant id | _auto_ |
| `ACA_CONNECTOR_CONNECTION_RUNTIME_URL` | Connection runtime URL (used in the `gatewayConnections[]` wiring) | _auto_ |
| `ACA_SANDBOX_GROUP_PRINCIPAL_ID` | Sandbox-group MI principal id (oid) | _auto_ |

Run either flow, both, or switch between them without losing state.

## Quickstart - azd

```bash
cd ..                # scenario root (contains azure.yaml)
azd auth login
az login             # the postprovision hook also needs the az CLI
azd up
```

Bicep creates only the resource group; the postprovision hook delegates
to `samples/sandboxes/setup/python/setup.py` + this scenario's
`setup/python/setup.py` (interactive OAuth consent included). See the
[scenario README](../README.md#quickstart-with-azd-up) for details.

## Quickstart - Python

```bash
cd python
pip install -r requirements.txt
python setup.py
```

## Quickstart - CLI

```bash
cd cli
./setup.sh
```

> On Windows, run from Git Bash, WSL, or MSYS2.

## OAuth consent

On first run, if the Office 365 connection is not yet `Connected`, the
setup script will:

1. Generate a one-time consent URL.
2. Print it and (Python only) try to open it in your default browser.
3. Pause until you press Enter.
4. Verify the connection status is `Connected` (else exit with the URL
   printed so you can retry).

The consent link is short-lived — click it as soon as it's printed. If
you miss the window, re-run setup.

## Re-running setup

Both flows are idempotent — re-running is safe. The gateway, connection,
and access policy are created with `PUT` (upsert). The script prints
which step it skipped (`already exists`).

> **Concurrency note.** The sandbox group's `gatewayConnections[]` is an
> ARM array property; ARM `PATCH` replaces the whole array. Both flows
> do a `GET` → merge-by-`resourceId` → `PATCH` to preserve unrelated
> entries (e.g. MCP-server entries from other samples). This is **not**
> protected by ETags, so two operators running setup/teardown against
> the same sandbox group at the same time may clobber each other's
> writes (last write wins). For sample-scale single-operator use this
> is fine; in shared lab environments, coordinate or extend the helper
> to retry on conflict.

## Teardown

Deletes the connector gateway (along with all its connections, trigger
configs, and access policies) and clears the trigger-related keys from
`samples/.env`. The sandboxes baseline is **not** touched — use the
sandboxes pillar's teardown for the resource group / sandbox group.

```bash
python python/teardown.py            # or: python/teardown.py --yes
./cli/teardown.sh                    # or: ./cli/teardown.sh --yes
```
