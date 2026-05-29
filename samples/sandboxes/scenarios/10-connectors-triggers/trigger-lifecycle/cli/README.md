# Trigger lifecycle (CLI)

Bash equivalent of `../python/trigger.py`. Uses the `aca` CLI for
sandbox / port operations and `az rest` for trigger config CRUD.

## Prerequisites

- Both prerequisites applied:
  - `../../../../sandboxes/setup/cli/setup.sh`
  - `../../../setup/cli/setup.sh`
- `az login` and `aca` on PATH (the sandboxes setup installs `aca`).

## Run

```bash
./run.sh
```

## What it does

Same as the Python script: discovers operations, creates a sandbox with
a Python stdlib listener on :5000, adds the port with the gateway MI
in `entraId.objectIds`, PUTs a trigger config, lists, disables,
enables, and tears everything down in the right order
(**trigger → port → sandbox**).
