# 12 - Interactive shell (CLI)

```bash
# One-time, from samples/sandboxes/setup/cli/:  ./setup.sh
./run.sh
```

The script boots a sandbox, hands you an interactive shell via
`aca sandbox shell`, and deletes the sandbox when you exit
(Ctrl-D / `exit`) - even if you abort with Ctrl-C.

## What this shows

| Command | What it does |
|---|---|
| `aca sandbox create --disk ubuntu` | Boot an Ubuntu sandbox |
| `aca sandbox shell --id <id>` | Open an interactive PTY (defaults to `/bin/bash`) |
| `aca sandbox shell --id <id> --command /bin/sh` | Use a different shell |
| `aca sandbox delete --id <id> --yes` | Tear it down (in `trap` / `finally`) |

The scripts auto-load `samples/.env`, so `aca` finds your subscription,
resource group, and sandbox group without any manual exports.
