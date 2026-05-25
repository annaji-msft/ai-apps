"""Getting started - create a sandbox, run a command, delete it.

Shows two flavors of `begin_create_sandbox`:

1. **Basic** - just `disk="ubuntu"`; every other knob takes its default.
2. **Advanced** - explicit `cpu`, `memory`, `auto_suspend_seconds`,
   `labels`, `environment` to show how to override the defaults.

Configuration comes from samples/.env (written by
samples/sandboxes/setup/python/setup.py).
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
    """Load samples/.env; exit with a friendly error if it isn't there yet."""
    for parent in Path(__file__).resolve().parents:
        env = parent / ".env"
        if env.is_file():
            for line in env.read_text().splitlines():
                if line and not line.startswith("#") and "=" in line:
                    k, v = line.split("=", 1)
                    os.environ.setdefault(k.strip(), v.strip())
            break
    if not os.environ.get("ACA_SANDBOXGROUP_REGION"):
        sys.exit(
            "error: samples/.env is missing required keys. Run:\n"
            "       python samples/sandboxes/setup/python/setup.py"
        )


def _print_exec(label: str, result) -> None:
    print(f"--- {label} ---")
    if result.stdout:
        sys.stdout.write(result.stdout)
        if not result.stdout.endswith("\n"):
            sys.stdout.write("\n")
    if result.stderr:
        sys.stderr.write(result.stderr)
    if result.exit_code != 0:
        sys.exit(f"command exited with code {result.exit_code}")


def main() -> None:
    _load_env()
    subscription_id = os.environ["AZURE_SUBSCRIPTION_ID"]
    resource_group = os.environ["ACA_RESOURCE_GROUP"]
    sandbox_group = os.environ["ACA_SANDBOX_GROUP"]
    region = os.environ["ACA_SANDBOXGROUP_REGION"]

    credential = DefaultAzureCredential()
    client = SandboxGroupClient(
        endpoint_for_region(region),
        credential,
        subscription_id=subscription_id,
        resource_group=resource_group,
        sandbox_group=sandbox_group,
    )

    basic = None
    advanced = None
    try:
        # ----------------------------------------------------------------
        # Basic create -- disk=ubuntu and that's it. Every other knob
        # takes its default. Listed here so you know what you're getting:
        #
        #   cpu="1000m"              # 1 vCPU
        #   memory="2048Mi"          # 2 GiB
        #   auto_suspend_seconds=300 # 5 min idle -> suspend
        #   labels=None              # no labels
        #   environment=None         # no extra env vars
        #   connections=None         # no SandboxGroupConnection refs
        #   ports=None               # no exposed ports
        #   egress_policy=None       # inherit group egress policy
        #   polling_timeout=300      # max wait for Running state
        #   polling_interval=3       # seconds between status polls
        # ----------------------------------------------------------------
        print("==> Creating basic sandbox (defaults)...")
        basic = client.begin_create_sandbox(disk="ubuntu").result()
        print(f"    sandbox: {basic.sandbox_id}")
        _print_exec("basic exec", basic.exec("echo hello world && uname -a"))

        # ----------------------------------------------------------------
        # Advanced create -- override the common knobs. Anything not
        # listed still falls back to the defaults shown above.
        # ----------------------------------------------------------------
        print("==> Creating advanced sandbox (explicit cpu/memory/env/labels)...")
        advanced = client.begin_create_sandbox(
            disk="ubuntu",
            cpu="2000m",                       # 2 vCPU
            memory="4096Mi",                   # 4 GiB
            auto_suspend_seconds=600,          # 10 min idle -> suspend
            labels={"sample": "01-sandboxes", "tier": "advanced"},
            environment={"GREETING": "hello from advanced sandbox"},
        ).result()
        print(f"    sandbox: {advanced.sandbox_id}")
        _print_exec(
            "advanced exec",
            advanced.exec("echo $GREETING && nproc && free -m | head -n2"),
        )
    finally:
        if basic is not None:
            print(f"==> Deleting basic sandbox {basic.sandbox_id}...")
            basic.delete()
        if advanced is not None:
            print(f"==> Deleting advanced sandbox {advanced.sandbox_id}...")
            advanced.delete()
        client.close()
        credential.close()

    print("==> Done.")


if __name__ == "__main__":
    main()
