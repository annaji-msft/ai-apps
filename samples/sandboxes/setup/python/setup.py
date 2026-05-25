"""Provision the baseline infrastructure for the sandboxes pillar (Python flow).

Creates (all idempotent):

  1. Resource group           via azure-mgmt-resource
  2. Sandbox group            via azure.containerapps.sandbox.SandboxGroupManagementClient
  3. Data-owner role          via azure-mgmt-authorization
                              (Container Apps SandboxGroup Data Owner,
                               assigned to current principal at RG scope)

Writes ``samples/.env`` so every guide can find the configuration.

This script does NOT install or configure the ``aca`` CLI — for that,
use ``../cli/setup.sh`` — bash runs on Linux, macOS, and Windows
(Git Bash / WSL / MSYS2).
The two flows share state via ``samples/.env``; run one or both in any order.

Prerequisites:
  * Azure CLI installed and `az login` completed (or any other
    DefaultAzureCredential source)
  * Python 3.10+

Override defaults with environment variables:

  AZURE_SUBSCRIPTION_ID       (auto-detected from `az account show` if unset)
  ACA_RESOURCE_GROUP          default: ai-apps-samples-rg
  ACA_SANDBOX_GROUP           default: ai-apps-samples-group
  ACA_SANDBOXGROUP_REGION     default: westus2

Run:

  pip install -r requirements.txt
  python setup.py
"""

from __future__ import annotations

import base64
import json
import os
import subprocess
import sys
import time
import uuid
from pathlib import Path

from azure.core.exceptions import HttpResponseError
from azure.identity import DefaultAzureCredential
from azure.mgmt.authorization import AuthorizationManagementClient
from azure.mgmt.resource import ResourceManagementClient
from azure.containerapps.sandbox import SandboxGroupManagementClient

ROLE_NAME = "Container Apps SandboxGroup Data Owner"
DEFAULTS = {
    "ACA_RESOURCE_GROUP": "ai-apps-samples-rg",
    "ACA_SANDBOX_GROUP": "ai-apps-samples-group",
    "ACA_SANDBOXGROUP_REGION": "westus2",
}
SAMPLES_DIR = Path(__file__).resolve().parents[3]  # samples/
ENV_FILE = SAMPLES_DIR / ".env"


def _detect_subscription_id() -> str:
    value = os.environ.get("AZURE_SUBSCRIPTION_ID")
    if value:
        return value
    try:
        out = subprocess.run(
            ["az", "account", "show", "-o", "json"],
            capture_output=True, text=True, check=True,
            shell=sys.platform == "win32",
        )
        return json.loads(out.stdout)["id"]
    except Exception as exc:
        sys.exit(
            "error: AZURE_SUBSCRIPTION_ID is unset and `az account show` "
            f"failed: {exc}"
        )


def _detect_principal() -> tuple[str, str]:
    """Return (oid, principal_type) for the current credential.

    Uses the JWT ``oid`` claim from the management token (works for both
    users and service principals; no Graph permission required).
    """
    token = DefaultAzureCredential().get_token(
        "https://management.azure.com/.default"
    )
    payload = token.token.split(".")[1]
    payload += "=" * (4 - len(payload) % 4)
    claims = json.loads(base64.urlsafe_b64decode(payload))
    oid = claims["oid"]
    idtyp = (claims.get("idtyp") or "").lower()
    if idtyp == "app":
        return oid, "ServicePrincipal"
    if idtyp == "user" or claims.get("upn") or claims.get("preferred_username"):
        return oid, "User"
    return oid, "ServicePrincipal"


def _ensure_role_assignment(
    auth_client: AuthorizationManagementClient,
    scope: str,
    principal_id: str,
    principal_type: str,
) -> None:
    role_defs = auth_client.role_definitions.list(
        scope, filter=f"roleName eq '{ROLE_NAME}'"
    )
    role_def = next(role_defs, None)
    if role_def is None:
        sys.exit(
            f"error: role '{ROLE_NAME}' not found at scope {scope}. "
            "Is the Microsoft.App provider registered in this subscription?"
        )
    try:
        auth_client.role_assignments.create(
            scope,
            str(uuid.uuid4()),
            {
                "role_definition_id": role_def.id,
                "principal_id": principal_id,
                "principal_type": principal_type,
            },
        )
        print(f"    assigned '{ROLE_NAME}' to {principal_type} {principal_id}")
    except HttpResponseError as exc:
        if "RoleAssignmentExists" in str(exc) or "Conflict" in str(exc):
            print(f"    role '{ROLE_NAME}' already assigned (skipping)")
        else:
            raise


def _write_env_file(values: dict[str, str]) -> None:
    """Merge values into samples/.env, preserving keys we don't own."""
    existing: dict[str, str] = {}
    if ENV_FILE.exists():
        for line in ENV_FILE.read_text().splitlines():
            if line and not line.startswith("#") and "=" in line:
                k, v = line.split("=", 1)
                existing[k.strip()] = v.strip()
    existing.update(values)
    lines = [
        "# Written by samples/sandboxes/setup/python/setup.py",
        "# Re-run python or cli setup to update.",
        "",
    ]
    for key in sorted(existing):
        lines.append(f"{key}={existing[key]}")
    ENV_FILE.write_text("\n".join(lines) + "\n")
    print(f"    wrote {ENV_FILE}")


def main() -> None:
    subscription_id = _detect_subscription_id()
    resource_group = os.environ.get("ACA_RESOURCE_GROUP", DEFAULTS["ACA_RESOURCE_GROUP"])
    sandbox_group = os.environ.get("ACA_SANDBOX_GROUP", DEFAULTS["ACA_SANDBOX_GROUP"])
    region = os.environ.get("ACA_SANDBOXGROUP_REGION", DEFAULTS["ACA_SANDBOXGROUP_REGION"])

    print("==> Sandboxes pillar - Python SDK setup")
    print(f"    subscription:   {subscription_id}")
    print(f"    resource group: {resource_group}")
    print(f"    sandbox group:  {sandbox_group}")
    print(f"    region:         {region}")

    credential = DefaultAzureCredential()

    print(f"==> Ensuring resource group '{resource_group}' in {region}...")
    rm = ResourceManagementClient(credential, subscription_id)
    rm.resource_groups.create_or_update(resource_group, {"location": region})

    print(f"==> Ensuring sandbox group '{sandbox_group}'...")
    mgmt = SandboxGroupManagementClient(
        credential,
        subscription_id=subscription_id,
        resource_group=resource_group,
    )
    try:
        mgmt.create_group(sandbox_group, location=region)
    except HttpResponseError as exc:
        if exc.status_code == 409 and "already exists" in str(exc).lower():
            print("    sandbox group already exists (skipping)")
        else:
            raise

    print(f"==> Assigning '{ROLE_NAME}'...")
    principal_id, principal_type = _detect_principal()
    auth = AuthorizationManagementClient(credential, subscription_id)
    rg_scope = f"/subscriptions/{subscription_id}/resourceGroups/{resource_group}"
    _ensure_role_assignment(auth, rg_scope, principal_id, principal_type)

    print(f"==> Writing {ENV_FILE.relative_to(SAMPLES_DIR.parent)}...")
    _write_env_file({
        "AZURE_SUBSCRIPTION_ID": subscription_id,
        "ACA_SUBSCRIPTION": subscription_id,
        "ACA_RESOURCE_GROUP": resource_group,
        "ACA_SANDBOX_GROUP": sandbox_group,
        "ACA_SANDBOXGROUP_REGION": region,
        "ACA_REGION": region,
    })

    print("==> Waiting briefly for RBAC propagation...")
    time.sleep(10)

    mgmt.close()
    auth.close()
    rm.close()
    credential.close()

    print("==> Done.")
    print()
    print("Next:  cd ../../guides/01-sandboxes/python && python sandboxes.py")


if __name__ == "__main__":
    main()
