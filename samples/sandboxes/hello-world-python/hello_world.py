"""Hello World sample for the Azure Container Apps Sandbox Python SDK.

Creates an Ubuntu sandbox in an existing sandbox group, runs a command,
prints the output, and deletes the sandbox.

Prerequisites:
  - `az login`
  - A sandbox group exists and your principal has the
    "Container Apps SandboxGroup Data Owner" role on it.

Configure via environment variables:
  AZURE_SUBSCRIPTION_ID
  ACA_RESOURCE_GROUP
  ACA_SANDBOX_GROUP
  ACA_SANDBOXGROUP_REGION  (default: eastus2)
"""

from __future__ import annotations

import os
import sys

from azure.identity import DefaultAzureCredential
from azure.containerapps.sandbox import SandboxGroupClient, endpoint_for_region


def _require(name: str) -> str:
    value = os.environ.get(name)
    if not value:
        sys.exit(f"error: environment variable {name} is required")
    return value


def main() -> None:
    subscription_id = _require("AZURE_SUBSCRIPTION_ID")
    resource_group = _require("ACA_RESOURCE_GROUP")
    sandbox_group = _require("ACA_SANDBOX_GROUP")
    region = os.environ.get("ACA_SANDBOXGROUP_REGION", "eastus2")

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
        print(f"Creating sandbox in group '{sandbox_group}' ({region})...")
        sandbox = client.begin_create_sandbox(disk="ubuntu").result()
        print(f"Sandbox ready: {sandbox.id}")

        result = sandbox.exec("echo hello world && uname -a")
        if result.stdout:
            print(result.stdout, end="" if result.stdout.endswith("\n") else "\n")
        if result.stderr:
            print(result.stderr, file=sys.stderr, end="")
        if result.exit_code != 0:
            sys.exit(f"command exited with code {result.exit_code}")
    finally:
        if sandbox is not None:
            sandbox.delete()
            print(f"\nDeleted sandbox {sandbox.id}.")
        client.close()


if __name__ == "__main__":
    main()
