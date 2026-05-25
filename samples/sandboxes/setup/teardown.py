"""Tear down the baseline infrastructure for the sandboxes pillar.

Deletes the sandbox group, then the resource group. Run this when you're
finished with the samples.

  python teardown.py

By default this asks for confirmation. Pass --yes to skip.
"""

from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

from azure.core.exceptions import HttpResponseError
from azure.identity import DefaultAzureCredential
from azure.mgmt.resource import ResourceManagementClient
from azure.containerapps.sandbox import SandboxGroupManagementClient

SAMPLES_DIR = Path(__file__).resolve().parents[2]
ENV_FILE = SAMPLES_DIR / ".env"


def _load_env() -> None:
    if not ENV_FILE.exists():
        return
    for line in ENV_FILE.read_text().splitlines():
        if line and not line.startswith("#") and "=" in line:
            k, v = line.split("=", 1)
            os.environ.setdefault(k.strip(), v.strip())


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--yes", action="store_true", help="skip confirmation")
    args = parser.parse_args()

    _load_env()
    subscription_id = os.environ.get("AZURE_SUBSCRIPTION_ID")
    resource_group = os.environ.get("ACA_RESOURCE_GROUP")
    sandbox_group = os.environ.get("ACA_SANDBOX_GROUP")
    if not (subscription_id and resource_group and sandbox_group):
        sys.exit("error: samples/.env missing required keys - run setup.py first?")

    print(f"This will delete:")
    print(f"  sandbox group: {sandbox_group}")
    print(f"  resource group: {resource_group} (and ALL resources in it)")
    if not args.yes:
        reply = input("Continue? [y/N] ").strip().lower()
        if reply not in ("y", "yes"):
            print("aborted.")
            return

    credential = DefaultAzureCredential()

    print(f"==> Deleting sandbox group '{sandbox_group}'...")
    mgmt = SandboxGroupManagementClient(
        credential,
        subscription_id=subscription_id,
        resource_group=resource_group,
    )
    try:
        mgmt.delete_group(sandbox_group)
    except HttpResponseError as exc:
        if exc.status_code == 404:
            print("    sandbox group not found (already deleted)")
        else:
            print(f"    warning: {exc}")
    mgmt.close()

    print(f"==> Deleting resource group '{resource_group}' (background)...")
    rm = ResourceManagementClient(credential, subscription_id)
    try:
        rm.resource_groups.begin_delete(resource_group)
    except HttpResponseError as exc:
        if exc.status_code == 404:
            print("    resource group not found (already deleted)")
        else:
            print(f"    warning: {exc}")
    rm.close()
    credential.close()

    print("==> Done. (Resource group deletion runs in the background.)")


if __name__ == "__main__":
    main()
