"""Getting started - create a sandbox, run a command, delete it.

The minimal end-to-end trip through the sandboxes data plane. Reads
configuration from samples/.env (written by samples/sandboxes/setup/setup.py).
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
    for parent in Path(__file__).resolve().parents:
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

    sandbox = None
    try:
        print("==> Creating sandbox...")
        sandbox = client.begin_create_sandbox(disk="ubuntu").result()
        print(f"    sandbox: {sandbox.sandbox_id}")

        print("==> Running command in sandbox...")
        result = sandbox.exec("echo hello world && uname -a")
        if result.stdout:
            sys.stdout.write(result.stdout)
            if not result.stdout.endswith("\n"):
                sys.stdout.write("\n")
        if result.stderr:
            sys.stderr.write(result.stderr)
        if result.exit_code != 0:
            sys.exit(f"command exited with code {result.exit_code}")
    finally:
        if sandbox is not None:
            print(f"==> Deleting sandbox {sandbox.sandbox_id}...")
            sandbox.delete()
        client.close()
        credential.close()

    print("==> Done.")


if __name__ == "__main__":
    main()
