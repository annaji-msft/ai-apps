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
| 01 | [webapps](scenarios/01-webapps) | Run a web app in a sandbox; patterns include `simple-anonymous` (open to the internet) and (planned) `authenticated` (Entra-gated) | ✅ ready |
| 02 | [coding-agents](scenarios/02-coding-agents) | Run **Copilot CLI** in a sandbox with deny-default egress + portal-paste PAT injection (Python + CLI). Claude Code / Codex stubs included. | ✅ Copilot CLI ready |
| 03 | [code-interpreter](scenarios/03-code-interpreter) | LLM-driven code execution — generate, run, observe, iterate | 📝 planned |
| 04 | [swarms](scenarios/04-swarms) | Orchestrator coordinating many sandbox workers — variants 01 (sandbox inception: orchestrator sandbox spawns workers in another group via its group's MI) and 02 (same plus an AzureBlob volume as durable shared scratchpad) ship now | ✅ ready |
| 05 | [data-processing](scenarios/05-data-processing) | Producer/consumer pipelines on shared AzureBlob volumes | 📝 planned |
| 06 | [developer-workflows](scenarios/06-developer-workflows) | PR builds, ephemeral CI, on-demand dev environments | 📝 planned |
| 07 | [computer-use](scenarios/07-computer-use) | Browser/desktop automation inside a sandbox for agentic UI tasks | 📝 planned |
| 08 | [sandbox-agents](scenarios/08-sandbox-agents) | Agent frameworks (OpenAI Agents SDK, Claude Managed Agents, LangChain Deep Agents) using ACA sandboxes as their tool-execution backend. OpenAI ships a **first-class provider package** (`agents_aca_sandboxes`) plus a live Deep Research demo and a platform-architecture brief. | ✅ OpenAI provider + demo |

## Reference

- [Python SDK README](https://github.com/microsoft/azure-container-apps/blob/main/docs/early/python-sdk/README.md)
- [ACA CLI README](https://github.com/microsoft/azure-container-apps/blob/main/docs/early/aca-cli/README.md)
