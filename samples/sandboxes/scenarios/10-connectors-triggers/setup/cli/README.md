# Connector-gateway scenario - CLI setup

Bash + `az rest`. Mirrors the Python flow in `../python/setup.py`.

## Prerequisites

- Sandboxes baseline already provisioned
  (`samples/sandboxes/setup/cli/setup.sh` or `.../python/setup.py`).
- `az login` complete.
- `python3` on `PATH`. The setup/teardown scripts shell out to short
  inline `python3` snippets for safe JSON GET-merge-PATCH of the sandbox
  group's `gatewayConnections[]` (an ARM array property that the
  current `az` CLI cannot mutate in place without clobbering peers).

## Run

```bash
./setup.sh
./setup.sh --non-interactive   # don't open browser; exit 2 if consent needed
```

If you see a **consent URL**, click it immediately (it expires fast).
Sign in with the Office 365 account whose inbox you want to wire into
the trigger.

## Override defaults

| Env var | Default |
|---|---|
| `ACA_CONNECTOR_GATEWAY` | `ai-apps-samples-gw` |
| `ACA_CONNECTOR_GATEWAY_REGION` | `ACA_SANDBOXGROUP_REGION` |
| `ACA_CONNECTOR_CONNECTION` | `o365-conn` |

## Teardown

```bash
./teardown.sh         # interactive
./teardown.sh --yes   # no prompt
```
