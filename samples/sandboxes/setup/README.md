# Sandboxes pillar - setup

Provisions the baseline infrastructure every sample in `samples/sandboxes`
needs:

1. A **resource group** to hold everything
2. A **sandbox group** (the data-plane endpoint for creating sandboxes)
3. The **Container Apps SandboxGroup Data Owner** role assigned to your
   current principal at the resource-group scope, so every sandbox group
   you create under it inherits the permission

Run once. Re-running is safe (everything is idempotent).

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

The script writes the resulting values to `samples/.env`. Every other
sample in this pillar reads from that file automatically - you do not
need to export any environment variables to run them.

## Teardown

```bash
python teardown.py            # asks for confirmation
python teardown.py --yes      # no prompt
```

Deletes the sandbox group and the resource group (everything in it).
