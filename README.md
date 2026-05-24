# ACA Sandboxes — Samples

Runnable samples for **Azure Container Apps sandboxes**, demonstrating both the
[`aca` CLI](https://github.com/microsoft/azure-container-apps/blob/main/docs/early/aca-cli/README.md)
and the [Python SDK](https://github.com/microsoft/azure-container-apps/blob/main/docs/early/python-sdk/README.md).

> Installation, authentication, and one-time setup (resource group, sandbox
> group, role assignment) live in the upstream READMEs linked below. Start
> there, then come back here to run the samples.

## Upstream docs

| Surface | README | What you'll find |
|---------|--------|------------------|
| ACA CLI (Early Access) | [aca-cli/README.md](https://github.com/microsoft/azure-container-apps/blob/main/docs/early/aca-cli/README.md) | Install scripts (Linux/macOS/Windows), `aca` command reference, sandbox group setup, role assignment. |
| Python SDK (Early Access) | [python-sdk/README.md](https://github.com/microsoft/azure-container-apps/blob/main/docs/early/python-sdk/README.md) | `pip install` instructions, `DefaultAzureCredential` auth, full API reference, async support. |

## Samples in this folder

See [`samples/`](samples) for runnable examples.

| Sample | Description |
|--------|-------------|
| [`samples/sandboxes/hello-world-python`](samples/sandboxes/hello-world-python) | Minimal Python SDK sample — create a sandbox, run a command, delete it. |
| [`samples/sandboxes/hello-world-cli`](samples/sandboxes/hello-world-cli) | Minimal `aca` CLI sample (Bash + PowerShell) — create a sandbox, run a command, delete it. |

More samples (snapshots, ports, egress policies, sandbox inception, cross-group
orchestration, async/parallel) will be added under `samples/sandboxes/`.
