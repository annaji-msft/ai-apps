# Connector-gateway scenario - Python setup

Provisions the connector-gateway baseline:

| Step | What it creates |
|---|---|
| 1 | Connector gateway with SystemAssigned MI (`Microsoft.Web/connectorGateways`) |
| 2 | Office 365 connection on the gateway |
| 3 | One-time OAuth consent flow if the connection isn't already `Connected` |
| 4a | Access policy: gateway MI → connection (so it can subscribe to events) |
| 4b | Access policy: sandbox-group MI → connection (so sandboxes can call its runtime URL) |
| 4c | Sandbox-group `gatewayConnections[]` entry wiring the connection's `connectionRuntimeUrl` to `SystemAssignedManagedIdentity` (declarative outbound auth; per-sandbox egress Transform is no longer required) |
| 5 | Appends gateway / connection keys to `samples/.env` |

## Prerequisites

- Sandboxes baseline already provisioned
  (`samples/sandboxes/setup/python/setup.py` or `.../cli/setup.sh`).
- `az login` complete.

## Run

```bash
pip install -r requirements.txt
python setup.py
python setup.py --non-interactive   # don't open browser; exit 2 if consent needed
```

If you see a **consent URL**, click it immediately — it expires in a
minute or two. Sign in with the Office 365 account whose inbox you
want to wire into the trigger.

## Override defaults

| Env var | Default |
|---|---|
| `ACA_CONNECTOR_GATEWAY` | `ai-apps-samples-gw` |
| `ACA_CONNECTOR_GATEWAY_REGION` | `ACA_SANDBOXGROUP_REGION` |
| `ACA_CONNECTOR_CONNECTION` | `o365-conn` |

## Teardown

```bash
python teardown.py         # interactive
python teardown.py --yes   # no prompt
```

Deletes the gateway (and all of its connections + trigger configs)
and clears the trigger-related keys from `samples/.env`. The sandboxes
baseline is untouched.
