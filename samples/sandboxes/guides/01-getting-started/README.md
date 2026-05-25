# 01 - Getting started

Create a sandbox, run a shell command, delete it. The minimal end-to-end
trip through the data plane.

Choose your style:

- [`python/`](python/) - Python SDK
- [`cli/`](cli/) - `aca` CLI (bash + PowerShell)

Both variants read configuration from `samples/.env`, which is created
by running [`../../setup/python/setup.py`](../../setup/python/) **or**
[`../../setup/cli/setup.sh`](../../setup/cli/) /
[`setup.ps1`](../../setup/cli/) — pick one. Run it once before any guide.

## What you'll see

```
==> Creating sandbox...
    sandbox: 91d7...
==> Running command in sandbox...
hello world
Linux ... GNU/Linux
==> Deleting sandbox 91d7...
==> Done.
```
