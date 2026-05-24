# Getting Started — Python SDK

End-to-end "zero to sandbox" sample for the
[Azure Container Apps Sandbox Python SDK](https://github.com/microsoft/azure-container-apps/blob/main/docs/early/python-sdk/README.md).

A single Python script walks through every step from a fresh Azure subscription
to running a command in a sandbox:

1. Authenticate with `DefaultAzureCredential` (uses `az login` locally)
2. Create a resource group (`azure-mgmt-resource`)
3. Create a sandbox group via the ARM control plane
   (`SandboxGroupManagementClient`)
4. Assign the signed-in user the **Container Apps SandboxGroup Data Owner**
   role (`azure-mgmt-authorization`)
5. Create an Ubuntu sandbox via the data plane (`SandboxGroupClient`) and run
   `echo hello world && uname -a`
6. Delete the sandbox (the resource group and sandbox group are kept so you
   can re-run the script quickly)

## Prerequisites

- Python >= 3.10
- [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli) installed
  and `az login` completed
- An Azure subscription where you can create resource groups and assign roles

## Install

```bash
pip install -r requirements.txt
```

## Configure

```bash
export AZURE_SUBSCRIPTION_ID="$(az account show --query id -o tsv)"
export AZURE_PRINCIPAL_ID="$(az ad signed-in-user show --query id -o tsv)"

# Optional overrides:
# export ACA_RESOURCE_GROUP=aca-samples-rg
# export ACA_SANDBOX_GROUP=aca-samples-group
# export ACA_SANDBOXGROUP_REGION=eastus2
```

## Run

```bash
python getting_started.py
```

## Cleanup

The script deletes the sandbox it created. To remove the rest:

```python
from azure.identity import DefaultAzureCredential
from azure.mgmt.resource import ResourceManagementClient
from azure.containerapps.sandbox import SandboxGroupManagementClient

cred = DefaultAzureCredential()
sub = "<your-subscription-id>"

SandboxGroupManagementClient(
    cred, subscription_id=sub, resource_group="aca-samples-rg",
).delete_group("aca-samples-group")

ResourceManagementClient(cred, sub).resource_groups.begin_delete("aca-samples-rg")
```
