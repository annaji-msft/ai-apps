# Sandboxes

Isolated, on-demand VMs for AI agents and code execution.

## Prerequisites

Make sure you have all of the following before running any lab:

| | Required for | Install / docs |
|---|---|---|
| **Azure subscription** | everything | one with permission to create resource groups and assign roles |
| **Azure CLI** (`az`) | everything — used to authenticate | <https://learn.microsoft.com/cli/azure/install-azure-cli> |
| **`az login` completed** | everything | run `az login` once after installing the CLI |
| **Python 3.10+** + `pip` | Python guides + `setup/python/setup.py` | <https://www.python.org/downloads/> |
| **Bash** | CLI guides + `setup/cli/setup.sh` | built-in on Linux/macOS; on Windows use Git Bash, WSL, or MSYS2 |
| **`aca` CLI** | CLI guides | installed automatically by `setup/cli/setup.sh`, or follow <https://github.com/microsoft/azure-container-apps/blob/main/docs/early/aca-cli/README.md> |
| **`curl`** | the install script that pulls down `aca` | usually already present; on Windows it ships with Git for Windows / WSL |

You only need **one** of Python or Bash — pick the flow that matches the
guides you'll run. Both flows produce the same `samples/.env`, so you
can mix freely later.

## Quickstart

One-time baseline (resource group + sandbox group + RBAC). Pick the
flow that matches what you'll use the most — both write the same
`samples/.env` so you can switch freely later.

```bash
# Python SDK flow (needs Python 3.10+)
cd setup/python
pip install -r requirements.txt
python setup.py

# OR: aca CLI flow (no Python required)
cd setup/cli
./setup.sh
```

> On Windows, run from Git Bash, WSL, MSYS2 — any shell with `bash`.

Then run a sample — cd into any folder under `guides/` or `scenarios/`:

```bash
cd guides/01-sandboxes/python
pip install -r requirements.txt
python sandboxes.py
```

See [`setup/README.md`](setup/README.md) for the full setup
documentation and how to override defaults.

## Catalog

### Guides — one capability per script

| # | Guide | What it shows | Status |
|---|---|---|---|
| 00 | [sandbox-groups](guides/00-sandbox-groups) | Create group, assign role, run sandbox, delete group | ✅ ready |
| 01 | [sandboxes](guides/01-sandboxes) | Basic + advanced + parallel (asyncio) + YAML apply, all in one script | ✅ ready |
| 02 | [snapshots](guides/02-snapshots) | `create_snapshot`, restore into new sandbox | ✅ ready |
| 03 | [disks](guides/03-disks) | Build from container image **and** commit running sandbox to a disk (combined) | ✅ ready |
| 04 | [volumes](guides/04-volumes) | AzureBlob shared mounts across sandboxes | ✅ ready |
| 05 | [lifecycle](guides/05-lifecycle) | stop / resume + AutoSuspendPolicy + AutoDeletePolicy | ✅ ready |
| 06 | [ports](guides/06-ports) | `add_port(anonymous=True)`, hit public URL | ✅ ready |
| 07 | [files](guides/07-files) | write / read / stat / list / mkdir / delete | ✅ ready |
| 08 | [egress](guides/08-egress) | `set_egress_default("Deny")` + host allow rules | ✅ ready |
| 09 | [secrets](guides/09-secrets) | upsert / peek / list / delete (group-scoped) | ✅ ready |
| 10 | [identity](guides/10-identity) | Group identity (SystemAssigned / UserAssigned managed identity today; extensible) | ✅ ready |
| 11 | [labels](guides/11-labels) | `labels=` on create + `list_sandboxes(labels=…)` | ✅ ready |
| 12 | [interactive-shell](guides/12-interactive-shell) | `aca sandbox shell` — interactive PTY session (CLI only) | ✅ ready |
| 13 | [cli-reference](guides/13-cli-reference) | `aca` CLI reference — install, auth, help, config, doctor, YAML, selectors, output, verbose | ✅ ready |
| 14 | [sdk-reference](guides/14-sdk-reference) | Python SDK reference — install, clients, async, logging, exceptions, helpers, pollers | ✅ ready |

### Scenarios — composed use cases (with production tips)

| # | Scenario | What it will show | Status |
|---|---|---|---|
| 01 | [simple-anonymous-app](scenarios/01-simple-anonymous-app) | Hello-world Node.js web app in a sandbox; expose port 8080 to the open internet | ✅ ready |
| 02 | [entra-protected-app](scenarios/02-entra-protected-app) | Same app, but gate the port with Entra ID so only specific emails/tenants reach it | 📝 planned |
| 03 | [coding-agents](scenarios/03-coding-agents) | Run a coding agent (Claude Code / Codex / Copilot CLI) per task in a fresh sandbox | 📝 planned |
| 04 | [code-interpreter](scenarios/04-code-interpreter) | LLM-driven code execution — generate, run, observe, iterate | 📝 planned |
| 05 | [swarms](scenarios/05-swarms) | Many sandboxes, one orchestrator — fan-out work across N workers | 📝 planned |
| 06 | [data-processing](scenarios/06-data-processing) | Producer/consumer pipelines on shared AzureBlob volumes | 📝 planned |
| 07 | [developer-workflows](scenarios/07-developer-workflows) | PR builds, ephemeral CI, on-demand dev environments | 📝 planned |
| 08 | [computer-use](scenarios/08-computer-use) | Browser/desktop automation inside a sandbox for agentic UI tasks | 📝 planned |

## Reference

- [Python SDK README](https://github.com/microsoft/azure-container-apps/blob/main/docs/early/python-sdk/README.md)
- [ACA CLI README](https://github.com/microsoft/azure-container-apps/blob/main/docs/early/aca-cli/README.md)
