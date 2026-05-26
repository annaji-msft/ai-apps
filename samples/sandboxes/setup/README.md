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
| **`aca` CLI**  | [`cli/`](./cli/)       | You'll mostly run the CLI guides. **No Python required** — bash on Linux, macOS, or Windows (Git Bash / WSL / MSYS2). |

Both flows write the same keys to `samples/.env`
(`AZURE_SUBSCRIPTION_ID`, `ACA_SUBSCRIPTION`, `ACA_RESOURCE_GROUP`,
`ACA_SANDBOX_GROUP`, `ACA_SANDBOXGROUP_REGION`, `ACA_REGION`, plus
`ACA_USER_EMAIL` — the signed-in user, used by scenarios that expose
Entra-protected sandbox ports), so you can run either one, both, or
switch between them without losing state.

Service-principal callers don't have an email — `ACA_USER_EMAIL` is
left empty and a warning is printed. Set it manually in `samples/.env`
if you want to run the Entra-protected scenarios as that principal.

## Quickstart - Python

```bash
cd python
pip install -r requirements.txt
python setup.py
```

## Quickstart - CLI

```bash
cd cli
./setup.sh
```

> On Windows, run from Git Bash, WSL, MSYS2 — any shell with `bash`.

## Teardown

Use whichever folder you set up from:

```bash
python python/teardown.py            # or: python/teardown.py --yes
./cli/teardown.sh              # or: ./cli/teardown.sh --yes
```

All three delete the sandbox group and the resource group.
