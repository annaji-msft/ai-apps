# Sandboxes

Isolated, on-demand VMs for AI agents and code execution.

## Quickstart

```bash
# 1. One-time baseline (resource group + sandbox group + RBAC)
cd setup
pip install -r requirements.txt
python setup.py
cd ..

# 2. Run a sample — cd into any folder under guides/ or scenarios/
cd guides/01-getting-started/python
pip install -r requirements.txt
python getting_started.py
```

See [`setup/README.md`](setup/README.md) for what `setup.py` provisions
and how to override defaults.

## Catalog

### Guides — one capability per script

| # | Guide | What it shows | Status |
|---|---|---|---|
| 01 | [getting-started](guides/01-getting-started) | Create sandbox, exec command, delete | Phase 1 |
| 02 | files | write / read / stat / list / mkdir / delete | Phase 1 |
| 03 | ports | `add_port(anonymous=True)`, hit public URL | Phase 1 |
| 04 | snapshots | `create_snapshot`, restore into new sandbox | Phase 1 |
| 05 | egress | `set_egress_default("Deny")` + host allow rules | Phase 3 |
| 06 | secrets | upsert / peek / list / delete (group-scoped) | Phase 3 |
| 07 | volumes | AzureBlob + DataDisk mounts | Phase 3 |
| 08 | labels | `labels=` on create + `list_sandboxes(labels=…)` | Phase 3 |
| 09 | lifecycle | stop / resume + AutoSuspendPolicy | Phase 3 |
| 10 | custom-disks | `create_disk_image` from public + private (ACR) | Phase 3 |
| 11 | commit-to-disk | `sandbox.commit()` → boot new sandbox from result | Phase 3 |
| 12 | async | `aio` SDK + `asyncio.gather` basics | Phase 3 |
| 13 | managed-identity | SystemAssigned / UserAssigned identity on group | Phase 3 |

### Scenarios — composed use cases (with production tips)

| Scenario | Composes | Status |
|---|---|---|
| [web-app-deployment](scenarios/web-app-deployment) | files + ports + exec | Phase 1 |
| agent-swarm | 2 groups + MI + SDK-in-sandbox inception | Phase 2 |
| parallel-fan-out | aio SDK + `asyncio.gather` over N sandboxes | Phase 2 |
| data-pipeline | volumes + 2 sandboxes producer/consumer | Phase 3 |
| checkpoint-rollback | snapshot before risky op → restore on failure | Phase 3 |
| golden-image-workflow | custom disk → boot → configure → commit → reuse | Phase 3 |
| ai-coding-agent | secrets + egress + custom disk + commit | Phase 3 |

### Agents — drop-in coding-agent integrations

Coming in Phase 3. Run popular coding agents (Claude Code, OpenAI Codex,
GitHub Copilot CLI, LangChain, AutoGen) inside an ACA sandbox.

## Reference

- [Python SDK README](https://github.com/microsoft/azure-container-apps/blob/main/docs/early/python-sdk/README.md)
- [ACA CLI README](https://github.com/microsoft/azure-container-apps/blob/main/docs/early/aca-cli/README.md)
