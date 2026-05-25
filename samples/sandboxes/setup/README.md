# Sandboxes pillar - setup

The sandboxes pillar samples need a small one-time Azure baseline:

1. A resource group
2. A sandbox group inside it
3. The `Container Apps SandboxGroup Data Owner` role on the current
   principal at the resource-group scope
4. A `samples/.env` file that all guides (Python and CLI) read

Pick the flow that matches the surface you want to use:

| Flow | Folder | When to use |
|------|--------|-------------|
| **Python SDK** | [`python/`](./python/) | You'll mostly run the Python guides. Needs Python 3.10+ + pip. |
| **`aca` CLI**  | [`cli/`](./cli/)       | You'll mostly run the CLI guides. **No Python required** - bash on Linux/macOS, PowerShell on Windows. |

Both flows write the same six keys to `samples/.env`
(`AZURE_SUBSCRIPTION_ID`, `ACA_SUBSCRIPTION`, `ACA_RESOURCE_GROUP`,
`ACA_SANDBOX_GROUP`, `ACA_SANDBOXGROUP_REGION`, `ACA_REGION`), so you
can run either one, both, or switch between them without losing state.

## Quickstart - Python

```bash
cd python
pip install -r requirements.txt
python setup.py
```

## Quickstart - CLI (bash)

```bash
cd cli
./setup.sh
```

## Quickstart - CLI (PowerShell)

```powershell
cd cli
.\setup.ps1
```

## Teardown

Use whichever folder you set up from:

```bash
python python/teardown.py            # or: python/teardown.py --yes
./cli/teardown.sh                    # or: ./cli/teardown.sh --yes
.\cli\teardown.ps1                   # or: .\cli\teardown.ps1 --yes
```

All three delete the sandbox group and the resource group.
