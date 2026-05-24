# ACA

Runnable samples for **Azure Container Apps sandboxes**, exercising both the
[`aca` CLI](https://github.com/microsoft/azure-container-apps/blob/main/docs/early/aca-cli/README.md)
and the [Python SDK](https://github.com/microsoft/azure-container-apps/blob/main/docs/early/python-sdk/README.md).

> **Installation, authentication, and the full command / API reference live in
> the upstream repo: [microsoft/azure-container-apps](https://github.com/microsoft/azure-container-apps).**
> Start there, then come back to run the samples.

## Upstream docs

| Surface | README | What you'll find |
|---------|--------|------------------|
| ACA CLI (Early Access) | [docs/early/aca-cli/README.md](https://github.com/microsoft/azure-container-apps/blob/main/docs/early/aca-cli/README.md) | Install scripts for Linux/macOS/Windows, full `aca` command reference, sandbox group setup, role assignment, `aca doctor`. |
| Python SDK (Early Access) | [docs/early/python-sdk/README.md](https://github.com/microsoft/azure-container-apps/blob/main/docs/early/python-sdk/README.md) | `pip install` instructions, `DefaultAzureCredential` auth, full API reference, async support. |

## Samples

See [`samples/`](samples) for the runnable examples in this repo.

| Sample | Description |
|--------|-------------|
| [`samples/sandboxes/getting-started-cli`](samples/sandboxes/getting-started-cli) | End-to-end `aca` CLI walkthrough (Bash + PowerShell) — login, resource group, sandbox group, role assignment, create sandbox, exec command, cleanup. |
| [`samples/sandboxes/getting-started-python`](samples/sandboxes/getting-started-python) | Same end-to-end flow using the Python SDK. |

More samples (snapshots, ports, egress policies, sandbox inception, cross-group
orchestration, async/parallel) will be added under `samples/sandboxes/`.
