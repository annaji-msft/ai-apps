# Getting Started — ACA CLI

End-to-end "zero to sandbox" sample for the
[Azure Container Apps Sandboxes CLI](https://github.com/microsoft/azure-container-apps/blob/main/docs/early/aca-cli/README.md).

A single script walks through every step from a fresh Azure subscription to
running a command in a sandbox:

1. Verify `az login`
2. Create a resource group
3. Create a sandbox group (`aca sandboxgroup create --set-config`)
4. Grant the signed-in user the **Container Apps SandboxGroup Data Owner** role
5. Run `aca doctor` to verify the setup
6. Create an Ubuntu sandbox and run `echo hello world && uname -a`
7. Delete the sandbox (the resource group and sandbox group are kept so you can
   re-run the script quickly)

## Prerequisites

- [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli) installed
- [`aca` CLI](https://github.com/microsoft/azure-container-apps/blob/main/docs/early/aca-cli/README.md#installation)
  installed and on your `PATH`
- An Azure subscription where you can create resource groups and assign roles

## Configure (optional)

Defaults are baked in. Override with env vars if you want:

| Variable | Default |
|----------|---------|
| `ACA_RESOURCE_GROUP` | `aca-samples-rg` |
| `ACA_SANDBOX_GROUP` | `aca-samples-group` |
| `ACA_SANDBOXGROUP_REGION` | `eastus2` |

## Run

**Linux / macOS:**

```bash
./getting_started.sh
```

**Windows (PowerShell):**

```powershell
./getting_started.ps1
```

## Cleanup

The script deletes the sandbox it created. To remove the rest:

```bash
aca sandboxgroup delete --name aca-samples-group --yes
az group delete --name aca-samples-rg --yes --no-wait
```
