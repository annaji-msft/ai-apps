# Sandboxes pillar - CLI setup

Provisions the Azure baseline (resource group + sandbox group + RBAC)
for the sandboxes pillar using the `az` CLI + the `aca` CLI. **No
Python required.** Writes `samples/.env` so the Python guides can
read the same config if you switch later.

Does NOT install Python or the SDK — for that, use
[`../python/setup.py`](../python/setup.py). The two flows share state
via `samples/.env`; run one or both in any order.

## Prerequisites

- [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli)
  installed and `az login` completed
- Bash 4+ (Linux/macOS) **or** PowerShell 5+ (Windows / pwsh anywhere)
- A subscription where you can create resource groups and assign roles

The script will install the [`aca` CLI](https://github.com/microsoft/azure-container-apps/blob/main/docs/early/aca-cli/README.md)
for you if it's not already on PATH.

## Run

```bash
# Linux / macOS
./setup.sh
```

```powershell
# Windows / pwsh
.\setup.ps1
```

Defaults (override with environment variables):

| Variable | Default |
|---|---|
| `AZURE_SUBSCRIPTION_ID` | auto-detected from `az account show` |
| `ACA_RESOURCE_GROUP` | `ai-apps-samples-rg` |
| `ACA_SANDBOX_GROUP` | `ai-apps-samples-group` |
| `ACA_SANDBOXGROUP_REGION` | `westus2` |

> The `aca` install script writes to `~/.aca/bin` and edits your user
> PATH. To pick up the change in your *current* shell after a fresh
> install, either restart the terminal or add `~/.aca/bin` to `PATH`
> manually. This setup script augments PATH for itself so the
> subsequent `aca` calls work in the same run.

## Teardown

```bash
./teardown.sh            # asks for confirmation
./teardown.sh --yes      # no prompt
```

```powershell
.\teardown.ps1
.\teardown.ps1 --yes
```

Deletes the sandbox group and the resource group (everything in it).
