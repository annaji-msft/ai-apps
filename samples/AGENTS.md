# Agent guide

Conventions and idioms for coding agents (GitHub Copilot, Claude Code,
Codex, Cursor, etc.) generating code that targets this repo's pillars.

## When to use which pillar

| The user wants to... | Pillar | Example sample to imitate |
|---|---|---|
| Run untrusted / agent-generated code in isolation | `sandboxes/` | `sandboxes/guides/01-getting-started` |
| Deploy a long-running HTTP service | `apps/` | `apps/guides/01-getting-started` (Phase 4) |
| Connect an app to Cosmos / Storage / Azure OpenAI | `connectors/` | `connectors/guides/01-getting-started` (Phase 6) |
| Kick off work from an event / HTTP / schedule | `triggers/` | `triggers/guides/01-getting-started` (Phase 7) |
| Build a real AI app composing two or more of the above | `ai-app-workloads/` | (Phase 8) |

## Setup pattern

Every pillar has its own `setup/` script. It is idempotent — re-running
it is safe.

```bash
cd samples/<pillar>/setup
pip install -r requirements.txt
python setup.py
```

`setup.py` writes `samples/.env`. All per-sample scripts walk up parent
directories to find that `.env` automatically — never ask the user to set
environment variables manually.

## Python sample idioms

A canonical sample script looks like this:

```python
"""<One-line summary>.

<Two-to-four-sentence description of what this sample demonstrates.>
"""

from __future__ import annotations
import os
import sys
from pathlib import Path

from azure.identity import DefaultAzureCredential
from azure.containerapps.sandbox import (
    SandboxGroupClient,
    endpoint_for_region,
)


def _load_env() -> None:
    """Walk up from this script to find samples/.env and load it."""
    here = Path(__file__).resolve()
    for parent in here.parents:
        env = parent / ".env"
        if env.is_file():
            for line in env.read_text().splitlines():
                if line and not line.startswith("#") and "=" in line:
                    k, v = line.split("=", 1)
                    os.environ.setdefault(k.strip(), v.strip())
            return


def main() -> None:
    _load_env()
    subscription_id = os.environ["AZURE_SUBSCRIPTION_ID"]
    resource_group  = os.environ["ACA_RESOURCE_GROUP"]
    sandbox_group   = os.environ["ACA_SANDBOX_GROUP"]
    region          = os.environ["ACA_SANDBOXGROUP_REGION"]

    credential = DefaultAzureCredential()
    client = SandboxGroupClient(
        endpoint_for_region(region),
        credential,
        subscription_id=subscription_id,
        resource_group=resource_group,
        sandbox_group=sandbox_group,
    )

    sandbox = None
    try:
        print("==> Creating sandbox...")
        sandbox = client.begin_create_sandbox(disk="ubuntu").result()

        # ... the sample's actual demonstration goes here ...

        print("==> Done.")
    finally:
        if sandbox is not None:
            print(f"==> Cleaning up sandbox {sandbox.sandbox_id}...")
            sandbox.delete()
        client.close()


if __name__ == "__main__":
    main()
```

Rules:

1. **Always use `DefaultAzureCredential`.** Never prompt for credentials.
2. **Auto-discover config** via the `_load_env()` walker. Never require the
   user to export environment variables.
3. **Friendly step prints** with the `==>` prefix. Keep them concise.
4. **Try / finally cleanup.** Delete only what this script created. Never
   delete the shared sandbox group or resource group.
5. **One capability per guide.** A guide demonstrates one client method
   family. If you find yourself doing more than one thing, write a scenario
   instead.
6. **Scenarios get a "Production tips" section** in their README.

## CLI sample idioms (bash + powershell)

CLI variants are siblings of `python/` — each scenario / guide that supports
CLI ships `cli/getting_started.sh` and `cli/getting_started.ps1`. Both:

- Use `dirname "$0"` / `$PSScriptRoot` to locate themselves.
- Walk up to find `samples/.env` and `source` / dot-source it.
- Use the `aca` CLI for sandbox operations (`aca sandbox create`,
  `aca sandbox exec`, `aca sandboxgroup ...`).
- Clean up with `trap` / `try/finally` on errors.

## Things that are NOT in this repo

- No competitor product names, comparisons, or copied wording.
- No internal-only Azure resources (private ACR names, internal MI
  resource IDs, internal subscription IDs).
- No SDK wheels built from source — always install from the published
  early-access wheel URL in `samples/requirements.txt`.

## See also

- [`llms.txt`](llms.txt) — machine-readable catalog of every sample.
- [`README.md`](README.md) — human-readable catalog with status table.
