# 01 - Sandboxes

Create a sandbox, run a shell command, delete it. The minimal end-to-end
trip through the data plane.

Each sample creates **two** sandboxes back-to-back:

1. **Basic** - `disk="ubuntu"` and nothing else. Shows you what defaults
   you get for free.
2. **Advanced** - the same call with `cpu`, `memory`,
   `auto_suspend_seconds`, `labels`, `environment` set explicitly, so
   you see how to override them.

Choose your style:

- [`python/`](python/) - Python SDK
- [`cli/`](cli/) - `aca` CLI (bash)

Both variants read configuration from `samples/.env`, which is created
by running [`../../setup/python/setup.py`](../../setup/python/) **or**
[`../../setup/cli/setup.sh`](../../setup/cli/) - pick one. Run it once
before any guide.

## Defaults

What the basic create accepts implicitly, and how to override each:

| Knob | Default | Python keyword | CLI flag |
| --- | --- | --- | --- |
| Disk image | `ubuntu` | `disk="ubuntu"` | `--disk ubuntu` |
| CPU | `1000m` (1 vCPU) | `cpu="1000m"` | `--cpu 1000m` |
| Memory | `2048Mi` (2 GiB) | `memory="2048Mi"` | `--memory 2048Mi` |
| Auto-suspend | 300 s (5 min idle) | `auto_suspend_seconds=300` | _(group default; no flag)_ |
| Labels | none | `labels={"k": "v"}` | `--label k=v` (repeatable) |
| Environment | none | `environment={"K": "v"}` | `--env K=v` (repeatable) |
| Exposed ports | none | `ports=[...]` | _(see guide 03-ports)_ |
| Egress policy | inherits group | `egress_policy=...` | _(see guide 05-egress)_ |

Other public keywords on `begin_create_sandbox`: `disk_id`,
`snapshot_id`, `preset`, `connections`, `volumes`, `entrypoint`, `cmd`,
`skip_egress_proxy`, `polling_timeout` (300), `polling_interval` (3).

## What you'll see

```
==> Creating basic sandbox (defaults)...
    sandbox: 91d7...
--- basic exec ---
hello world
Linux ... GNU/Linux
==> Creating advanced sandbox (explicit cpu/memory/env/labels)...
    sandbox: a3f2...
--- advanced exec ---
hello from advanced sandbox
2
              total        used        free      ...
Mem:           3936          ...
==> Deleting basic sandbox 91d7...
==> Deleting advanced sandbox a3f2...
==> Done.
```
