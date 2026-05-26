# 01 - Sandboxes (CLI)

```bash
# One-time, from samples/sandboxes/setup/cli/:  ./setup.sh
./run.sh
```

## What this shows

| Command | What it does |
|---|---|
| `aca sandbox create --disk ubuntu` | Boot an Ubuntu sandbox (flags) |
| `aca sandbox exec --id <id> -c "..."` | Run a shell command |
| `aca sandbox list` / `aca sandbox get --id <id>` | Inspect what's running |
| `aca sandbox apply --file sandbox.yaml` | Boot from a declarative spec |
| `aca sandbox delete --id <id> --yes` | Tear it down (in `trap` / `finally`) |

`run.sh` walks through a basic flag-based create, an advanced flag-based
create with `--cpu` / `--memory` / `--env` / `--label`, and finally an
`aca sandbox apply` against the `sandbox.yaml` next to it. The YAML
form is what you check into a repo so sandbox config lives next to your
source and shows up in code review.

The scripts auto-load `samples/.env`, so `aca` finds your subscription,
resource group, and sandbox group without any manual exports.
