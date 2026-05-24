# Samples

Runnable samples for Azure Container Apps sandboxes.

## Before you run a sample

Installation, authentication, and one-time setup (resource group, sandbox
group, role assignment) are documented in the upstream READMEs. Read them
first — every sample in this folder assumes that setup is already done.

| Surface | README | What you'll find |
|---------|--------|------------------|
| ACA CLI (Early Access) | [aca-cli/README.md](https://github.com/microsoft/azure-container-apps/blob/main/docs/early/aca-cli/README.md) | Install scripts for Linux/macOS/Windows, `aca` command reference, sandbox group setup, role assignment, `aca doctor`. |
| Python SDK (Early Access) | [python-sdk/README.md](https://github.com/microsoft/azure-container-apps/blob/main/docs/early/python-sdk/README.md) | `pip install` instructions, `DefaultAzureCredential` auth, full API reference, async support. |

## sandboxes/

| Sample | Description |
|--------|-------------|
| [`sandboxes/hello-world-python`](sandboxes/hello-world-python) | Minimal Python SDK sample — create a sandbox, run a command, delete it. |
| [`sandboxes/hello-world-cli`](sandboxes/hello-world-cli) | Minimal `aca` CLI sample (Bash + PowerShell) — create a sandbox, run a command, delete it. |

More samples (snapshots, ports, egress policies, sandbox inception, cross-group
orchestration, async/parallel) will be added here.
