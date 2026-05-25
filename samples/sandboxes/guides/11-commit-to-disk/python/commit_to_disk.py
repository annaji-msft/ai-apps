"""Commit to disk — freeze a primed sandbox into a reusable disk image.

Reads configuration from samples/.env (written by samples/sandboxes/setup/setup.py).
"""

from __future__ import annotations

import os
import time
import uuid
from pathlib import Path

from azure.identity import DefaultAzureCredential
from azure.containerapps.sandbox import SandboxGroupClient, endpoint_for_region


def _load_env() -> None:
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
    credential = DefaultAzureCredential()
    client = SandboxGroupClient(
        endpoint_for_region(os.environ["ACA_SANDBOXGROUP_REGION"]),
        credential,
        subscription_id=os.environ["AZURE_SUBSCRIPTION_ID"],
        resource_group=os.environ["ACA_RESOURCE_GROUP"],
        sandbox_group=os.environ["ACA_SANDBOX_GROUP"],
    )

    disk_name = f"committed-{uuid.uuid4().hex[:8]}"
    primer = clone = None
    disk_image_id = None

    try:
        print("==> Booting primer sandbox...")
        primer = client.begin_create_sandbox(labels={"guide": "commit"}).result()
        print(f"    primer: {primer.sandbox_id}")

        print("==> 'Priming' the sandbox: write /opt/marker.txt...")
        primer.exec('mkdir -p /opt && date -u +"baked-at: %Y-%m-%dT%H:%M:%SZ" > /opt/marker.txt')
        r = primer.exec("cat /opt/marker.txt")
        print(f"    {r.stdout.strip()}")

        print(f"\n==> begin_commit(name={disk_name!r})... (5-10 min)")
        disk = primer.begin_commit(name=disk_name, polling_timeout=1200).result()
        disk_image_id = disk.id
        print(f"    new disk: id={disk.id}  state={disk.status.state if disk.status else '?'}")

        # Delete primer before booting the clone to avoid sandbox-quota issues
        print("==> Deleting primer (no longer needed)...")
        primer.delete()
        primer = None
        time.sleep(5)

        print(f"\n==> Boot a NEW sandbox from disk {disk.id}...")
        clone = client.begin_create_sandbox(disk_id=disk.id, labels={"guide": "commit-clone"}).result()
        print(f"    clone: {clone.sandbox_id}")
        time.sleep(8)

        print("==> Verifying /opt/marker.txt is present in the clone...")
        content = clone.read_file("/opt/marker.txt")
        text = content.decode() if isinstance(content, (bytes, bytearray)) else content
        print(f"    {text.strip()}")
        assert "baked-at" in text
        print("    [ok] committed state preserved across boots")
    finally:
        for sbx in (primer, clone):
            if sbx is not None:
                try:
                    sbx.delete()
                except Exception:
                    pass
        if disk_image_id is not None:
            print(f"==> Deleting committed disk {disk_image_id}...")
            try:
                client.delete_disk_image(disk_image_id)
            except Exception as exc:
                print(f"    cleanup warning: {exc}")
        client.close()
        credential.close()


if __name__ == "__main__":
    main()
