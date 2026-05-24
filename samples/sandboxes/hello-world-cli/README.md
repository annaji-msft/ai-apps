# Hello World — ACA CLI

Minimal sample that uses the Azure Container Apps Sandboxes CLI to:

1. Create an Ubuntu sandbox in an existing sandbox group
2. Run `echo hello world && uname -a` inside it
3. Delete the sandbox

## Prerequisites

- [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli), logged in with `az login`
- The [`aca` CLI](https://github.com/microsoft/azure-container-apps/blob/main/docs/early/aca-cli/README.md)
  installed and on your `PATH`
- A sandbox group already created and your principal granted the
  `Container Apps SandboxGroup Data Owner` role on it
- The sandbox group selected as your active config:

  ```bash
  aca sandboxgroup create --name my-sandbox-group --location eastus2 --set-config
  ```

  Verify with `aca doctor`.

## Run

**Linux / macOS:**

```bash
./hello_world.sh
```

**Windows (PowerShell):**

```powershell
./hello_world.ps1
```

Expected output:

```
Creating sandbox...
Created sandbox: <sandbox-id>
hello world
Linux <hostname> ... x86_64 GNU/Linux
Deleted sandbox <sandbox-id>.
```
