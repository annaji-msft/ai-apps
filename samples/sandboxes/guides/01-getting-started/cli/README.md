# 01 - Getting started (CLI)

```bash
# One-time, from samples/sandboxes/setup/:  python setup.py
./run.sh              # bash / zsh
./run.ps1             # PowerShell
```

## What this shows

| Command | What it does |
|---|---|
| `aca sandbox create --disk ubuntu` | Boot an Ubuntu sandbox |
| `aca sandbox exec --id <id> -c "..."` | Run a shell command |
| `aca sandbox delete --id <id> --yes` | Tear it down (in `trap` / `finally`) |

The scripts auto-load `samples/.env`, so `aca` finds your subscription,
resource group, and sandbox group without any manual exports.
