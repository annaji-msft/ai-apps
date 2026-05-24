"""Getting Started — Azure Container Apps Sandbox Python SDK.

End-to-end "zero to sandbox" sample. Walks through every step from a fresh
Azure subscription to running a command in a sandbox:

  1. Authenticate via DefaultAzureCredential (uses `az login` locally)
  2. Create a resource group
  3. Create a sandbox group (ARM control plane)
  4. Grant the signed-in user the "Container Apps SandboxGroup Data Owner" role
  5. Create an Ubuntu sandbox and run `echo hello world && uname -a`
  6. Delete the sandbox (the resource group and sandbox group are kept so you
     can re-run the script quickly)

Required env vars:
  AZURE_SUBSCRIPTION_ID     your Azure subscription id
  AZURE_PRINCIPAL_ID        object id of the signed-in user / service principal
                            (`az ad signed-in-user show --query id -o tsv`)

Optional env vars (defaults shown):
  ACA_RESOURCE_GROUP        aca-samples-rg
  ACA_SANDBOX_GROUP         aca-samples-group
  ACA_SANDBOXGROUP_REGION   eastus2
"""

from __future__ import annotations

import os
import sys
import time
import uuid

from azure.core.exceptions import HttpResponseError
from azure.identity import DefaultAzureCredential
from azure.mgmt.authorization import AuthorizationManagementClient
from azure.mgmt.resource import ResourceManagementClient
from azure.containerapps.sandbox import (
    SandboxGroupClient,
    SandboxGroupManagementClient,
    endpoint_for_region,
)

ROLE_NAME = "Container Apps SandboxGroup Data Owner"


def _require(name: str) -> str:
    value = os.environ.get(name)
    if not value:
        sys.exit(f"error: environment variable {name} is required")
    return value


def main() -> None:
    subscription_id = _require("AZURE_SUBSCRIPTION_ID")
    principal_id = _require("AZURE_PRINCIPAL_ID")
    resource_group = os.environ.get("ACA_RESOURCE_GROUP", "aca-samples-rg")
    sandbox_group = os.environ.get("ACA_SANDBOX_GROUP", "aca-samples-group")
    region = os.environ.get("ACA_SANDBOXGROUP_REGION", "eastus2")

    credential = DefaultAzureCredential()

    # 1. Resource group
    print(f"==> Creating resource group '{resource_group}' in {region}...")
    resource_client = ResourceManagementClient(credential, subscription_id)
    resource_client.resource_groups.create_or_update(
        resource_group, {"location": region}
    )

    # 2. Sandbox group
    print(f"==> Creating sandbox group '{sandbox_group}'...")
    mgmt = SandboxGroupManagementClient(
        credential,
        subscription_id=subscription_id,
        resource_group=resource_group,
    )
    mgmt.create_group(sandbox_group, location=region)

    # 3. Role assignment — Data Owner on the resource group scope
    print(f"==> Assigning '{ROLE_NAME}' to principal {principal_id}...")
    auth_client = AuthorizationManagementClient(credential, subscription_id)
    scope = f"/subscriptions/{subscription_id}/resourceGroups/{resource_group}"
    role_def = next(
        auth_client.role_definitions.list(scope, filter=f"roleName eq '{ROLE_NAME}'")
    )
    try:
        auth_client.role_assignments.create(
            scope,
            str(uuid.uuid4()),
            {
                "role_definition_id": role_def.id,
                "principal_id": principal_id,
                "principal_type": "User",
            },
        )
    except HttpResponseError as exc:
        if "RoleAssignmentExists" in str(exc) or "Conflict" in str(exc):
            print("    (role already assigned; continuing)")
        else:
            raise
    # Give RBAC a moment to propagate before hitting the data plane.
    time.sleep(15)

    # 4. Create sandbox and run a command
    print("==> Creating sandbox...")
    client = SandboxGroupClient(
        endpoint_for_region(region),
        credential,
        subscription_id=subscription_id,
        resource_group=resource_group,
        sandbox_group=sandbox_group,
    )
    sandbox = None
    try:
        sandbox = client.begin_create_sandbox(disk="ubuntu").result()
        print(f"    sandbox: {sandbox.id}")

        print("==> Running command in sandbox...")
        result = sandbox.exec("echo hello world && uname -a")
        if result.stdout:
            print(result.stdout, end="" if result.stdout.endswith("\n") else "\n")
        if result.stderr:
            print(result.stderr, file=sys.stderr, end="")
        if result.exit_code != 0:
            sys.exit(f"command exited with code {result.exit_code}")
    finally:
        if sandbox is not None:
            print(f"==> Deleting sandbox {sandbox.id}...")
            sandbox.delete()
        client.close()
        mgmt.close()

    print("==> Done.")


if __name__ == "__main__":
    main()
