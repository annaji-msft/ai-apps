# Hello World — Python SDK

Minimal sample that uses the Azure Container Apps Sandbox Python SDK to:

1. Connect to an existing sandbox group
2. Create an Ubuntu sandbox
3. Run `echo hello world && uname -a` inside it
4. Print the output and clean up

## Prerequisites

- Python >= 3.10
- [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli), logged in with `az login`
- An Azure subscription with a resource group
- A sandbox group already created and your principal granted the
  `Container Apps SandboxGroup Data Owner` role on it
  (see the [Python SDK README](https://github.com/microsoft/azure-container-apps/blob/main/docs/early/python-sdk/README.md)
  for one-time setup)

## Install

```bash
pip install -r requirements.txt
```

## Configure

Set the following environment variables (or edit `hello_world.py` directly):

```bash
export AZURE_SUBSCRIPTION_ID="$(az account show --query id -o tsv)"
export ACA_RESOURCE_GROUP="my-rg"
export ACA_SANDBOX_GROUP="my-sandbox-group"
export ACA_SANDBOXGROUP_REGION="eastus2"
```

## Run

```bash
python hello_world.py
```

Expected output:

```
Creating sandbox in group 'my-sandbox-group' (eastus2)...
Sandbox ready: <sandbox-id>
hello world
Linux <hostname> ... x86_64 GNU/Linux

Deleted sandbox <sandbox-id>.
```
