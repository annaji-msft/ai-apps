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
| 01 | [sandboxes](guides/01-sandboxes) | Create sandbox, exec command, delete | ✅ ready |
| 02 | [files](guides/02-files) | write / read / stat / list / mkdir / delete | ✅ ready |
| 03 | [ports](guides/03-ports) | `add_port(anonymous=True)`, hit public URL | ✅ ready |
| 04 | [snapshots](guides/04-snapshots) | `create_snapshot`, restore into new sandbox | ✅ ready |
| 05 | [egress](guides/05-egress) | `set_egress_default("Deny")` + host allow rules | ✅ ready |
| 06 | [secrets](guides/06-secrets) | upsert / peek / list / delete (group-scoped) | ✅ ready |
| 07 | [volumes](guides/07-volumes) | AzureBlob shared mounts across sandboxes | ✅ ready |
| 08 | [labels](guides/08-labels) | `labels=` on create + `list_sandboxes(labels=…)` | ✅ ready |
| 09 | [lifecycle](guides/09-lifecycle) | stop / resume + AutoSuspendPolicy + AutoDeletePolicy | ✅ ready |
| 10 | [disks](guides/10-disks) | Build from container image **and** commit running sandbox to a disk (combined) | ✅ ready |
| 11 | [async](guides/11-async) | `aio` SDK + `asyncio.gather` basics | ✅ ready |
| 12 | [managed-identity](guides/12-managed-identity) | SystemAssigned / UserAssigned identity on group | ✅ ready |
| 13 | [interactive-shell](guides/13-interactive-shell) | `aca sandbox shell` — interactive PTY session (CLI only) | ✅ ready |

### Deep dives — capabilities beyond the functional guides

Reference docs covering SDK and CLI capabilities that the numbered guides don't focus on. Each is a single README with anchor-linked sections — jump to whichever topic you need.

| Deep dive | Sections | Status |
|---|---|---|
| [SDK deep dive](guides/sdk) | Clients · Async · Logging · Exceptions · Helpers · Pollers | ✅ ready |
| [CLI deep dive](guides/cli) | Auth · Help commands · Config deep dive · `doctor` · YAML spec workflow · Selectors · Output formats · Verbose and debug | ✅ ready |

### Scenarios — composed use cases (with production tips)

| Scenario | Composes | Status |
|---|---|---|
| [web-app-deployment](scenarios/web-app-deployment) | files + ports + exec | ✅ ready |
| [agent-swarm](scenarios/agent-swarm) | aio SDK + orchestrator → mapper/reducer roles | ✅ ready |
| [parallel-fan-out](scenarios/parallel-fan-out) | aio SDK + `asyncio.gather` over N sandboxes | ✅ ready |
| data-pipeline | volumes + 2 sandboxes producer/consumer | Phase 3 |
| checkpoint-rollback | snapshot before risky op → restore on failure | Phase 3 |
| golden-image-workflow | custom disk → boot → configure → commit → reuse | Phase 3 |
| ai-coding-agent | secrets + egress + custom disk + commit | Phase 3 |
| claude-code-in-sandbox | run Claude Code CLI per task in fresh sandbox | Phase 3 |
| codex-in-sandbox | run OpenAI Codex CLI per task in fresh sandbox | Phase 3 |
| copilot-cli-in-sandbox | run GitHub Copilot CLI per task in fresh sandbox | Phase 3 |
| langchain-tool-runtime | sandbox as a LangChain `BashTool` backend | Phase 3 |
| autogen-code-executor | sandbox as an AutoGen `CodeExecutor` | Phase 3 |

## Reference

- [Python SDK README](https://github.com/microsoft/azure-container-apps/blob/main/docs/early/python-sdk/README.md)
- [ACA CLI README](https://github.com/microsoft/azure-container-apps/blob/main/docs/early/aca-cli/README.md)
