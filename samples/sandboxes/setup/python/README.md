# Sandboxes pillar - Python SDK setup

Provisions the Azure baseline (resource group + sandbox group + RBAC)
for the sandboxes pillar using the Python management SDK. Writes
`samples/.env` so every guide can find the configuration.

Does NOT install or configure the `aca` CLI — for that, use
[`../cli/setup.sh`](../cli/setup.sh) (Linux/macOS) or
[`..\cli\setup.ps1`](../cli/setup.ps1) (Windows). The two flows share
state via `samples/.env`; run one or both in any order.

## Prerequisites

- [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli)
  installed and `az login` completed
- Python 3.10+
- A subscription where you can create resource groups and assign roles

## Run

```bash
pip install -r requirements.txt
python setup.py
```

Defaults (override with environment variables):

| Variable | Default |
|---|---|
| `AZURE_SUBSCRIPTION_ID` | auto-detected from `az account show` |
| `ACA_RESOURCE_GROUP` | `ai-apps-samples-rg` |
| `ACA_SANDBOX_GROUP` | `ai-apps-samples-group` |
| `ACA_SANDBOXGROUP_REGION` | `westus2` |

## Teardown

```bash
python teardown.py            # asks for confirmation
python teardown.py --yes      # no prompt
```

Deletes the sandbox group and the resource group (everything in it).
