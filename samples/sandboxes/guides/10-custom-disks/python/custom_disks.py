"""Custom disk image — build from a public container image and boot from it.

For ACR (private) images, pass ``registry_credentials=RegistryCredentials(
username=..., password=...)`` or ``managed_identity_resource_id=...``
to ``begin_create_disk_image``.

Reads configuration from samples/.env (written by samples/sandboxes/setup/python/setup.py).
"""

from __future__ import annotations

import os
import uuid
from pathlib import Path

from azure.identity import DefaultAzureCredential
from azure.containerapps.sandbox import SandboxGroupClient, endpoint_for_region


BASE_IMAGE = "docker.io/library/alpine:3.19"


def _load_env() -> None:
    """Load samples/.env; exit with a friendly error if it isn't there yet."""
    import sys
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


def main() -> None:
    _load_env()
    credential = DefaultAzureCredential()
    client = SandboxGroupClient(
        endpoint_for_region(os.environ["ACA_SANDBOXGROUP_REGION"]),
        credential,
        subscription_id=os.environ["AZURE_SUBSCRIPTION_ID"],
        resource_group=os.environ["ACA_RESOURCE_GROUP"],
        sandbox_group=os.environ["ACA_SANDBOX_GROUP"],
    )

    disk_name = f"alpine-demo-{uuid.uuid4().hex[:8]}"
    disk_image_id = None
    sandbox = None

    try:
        print(f"==> begin_create_disk_image({BASE_IMAGE!r}, name={disk_name!r})...")
        print("    (this can take 5-10 minutes the first time)")
        poller = client.begin_create_disk_image(
            BASE_IMAGE, name=disk_name, polling_timeout=900,
        )
        disk = poller.result()
        disk_image_id = disk.id
        print(f"    built: id={disk.id}  state={disk.status.state if disk.status else '?'}")

        print(f"\n==> begin_create_sandbox(disk_id={disk.id})...")
        sandbox = client.begin_create_sandbox(disk_id=disk.id, labels={"guide": "custom-disk"}).result()
        print(f"    sandbox: {sandbox.sandbox_id}")

        print("\n==> Verifying — should be Alpine:")
        r = sandbox.exec("cat /etc/alpine-release || cat /etc/os-release | head -2")
        print(f"    {r.stdout.strip()}")
    finally:
        if sandbox is not None:
            print(f"\n==> Deleting sandbox {sandbox.sandbox_id}...")
            try:
                sandbox.delete()
            except Exception as exc:
                print(f"    cleanup warning: {exc}")
        if disk_image_id is not None:
            print(f"==> Deleting disk image {disk_image_id}...")
            try:
                client.delete_disk_image(disk_image_id)
            except Exception as exc:
                print(f"    cleanup warning: {exc}")
        client.close()
        credential.close()


if __name__ == "__main__":
    main()
