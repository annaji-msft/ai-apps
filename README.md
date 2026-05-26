# ai-apps

Runnable samples and reference scenarios for building **AI-native applications
on Azure Container Apps** — sandboxes, container apps, service connectors,
event triggers, and the cross-product workloads that compose them.

## Prerequisites

| | Required for | Install / docs |
|---|---|---|
| **Azure subscription** with permission to create resource groups and assign roles | everything | — |
| **Azure CLI** (`az`) + `az login` | everything | <https://learn.microsoft.com/cli/azure/install-azure-cli> |
| **Python 3.10+** + `pip` | Python guides + `setup/python/setup.py` | <https://www.python.org/downloads/> |
| **Bash** + **`curl`** | CLI guides + `setup/cli/setup.sh` | built-in on Linux/macOS; on Windows use Git Bash, WSL, or MSYS2 |
| **`aca` CLI** | CLI guides | installed automatically by `setup/cli/setup.sh` ([docs](https://github.com/microsoft/azure-container-apps/blob/main/docs/early/aca-cli/README.md)) |

You only need **one** of Python or Bash — pick the flow that matches the
guides you'll run.

## Quickstart

```bash
# 1. Authenticate
az login

# 2. Clone
git clone https://github.com/annaji-msft/ai-apps && cd ai-apps/samples

# 3. Provision the pillar you want to try (one-time per pillar)
cd sandboxes/setup/python && pip install -r requirements.txt && python setup.py
#  OR:  cd sandboxes/setup/cli && ./setup.sh

# 4. Run any sample — cd anywhere, the script just works
cd ../../guides/01-sandboxes/python
pip install -r requirements.txt
python sandboxes.py
```

Every sample is self-contained: `cd` into its folder, install its
`requirements.txt`, and run. Configuration is auto-discovered from the
`.env` file written by setup.

## Pillars

| Pillar | What it is | Start here |
|---|---|---|
| **[Sandboxes](samples/sandboxes)** | Isolated, on-demand VMs for AI agents and code execution | [`samples/sandboxes`](samples/sandboxes) |
| **[Container Apps](samples/containerapps)** | Long-running container apps and one-shot container apps jobs | [`samples/containerapps`](samples/containerapps) |
| **[Connectors](samples/connectors)** | Managed bindings to backing services (Cosmos, Storage, Azure OpenAI, Key Vault) | [`samples/connectors`](samples/connectors) |
| **[Triggers](samples/triggers)** | HTTP, event, scheduled, and KEDA-driven invocation patterns | [`samples/triggers`](samples/triggers) |
| **[AI app workloads](samples/ai-apps)** | Real-world scenarios composing two or more pillars | [`samples/ai-apps`](samples/ai-apps) |

Within each pillar:

- **`setup/`** — one Python script that provisions the pillar's baseline infra.
- **`guides/NN-*`** — one capability per script (~50 lines each).
- **`scenarios/*`** — composed real use cases with a narrative + production tips.
- **`agents/*`** (where applicable) — drop-in integrations for popular coding agents.

## Upstream docs

| Surface | Docs |
|---|---|
| Python SDK (Early Access) | [docs/early/python-sdk](https://github.com/microsoft/azure-container-apps/blob/main/docs/early/python-sdk/README.md) |
| ACA CLI (Early Access) | [docs/early/aca-cli](https://github.com/microsoft/azure-container-apps/blob/main/docs/early/aca-cli/README.md) |

## For coding agents

If you're a coding agent (GitHub Copilot, Claude Code, Codex, Cursor, etc.)
generating code that uses this repo:

- Start with [`samples/AGENTS.md`](samples/AGENTS.md) for idioms and conventions.
- See [`samples/llms.txt`](samples/llms.txt) for the machine-readable catalog.
