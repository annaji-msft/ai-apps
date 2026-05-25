"""Async SDK basics — concurrent exec calls on a single sandbox.

Reads configuration from samples/.env (written by samples/sandboxes/setup/python/setup.py).
"""

from __future__ import annotations

import asyncio
import os
import time
from pathlib import Path

from azure.identity.aio import DefaultAzureCredential
from azure.containerapps.sandbox import endpoint_for_region
from azure.containerapps.sandbox.aio import SandboxGroupClient


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


async def main() -> None:
    _load_env()
    credential = DefaultAzureCredential()
    client = SandboxGroupClient(
        endpoint_for_region(os.environ["ACA_SANDBOXGROUP_REGION"]),
        credential,
        subscription_id=os.environ["AZURE_SUBSCRIPTION_ID"],
        resource_group=os.environ["ACA_RESOURCE_GROUP"],
        sandbox_group=os.environ["ACA_SANDBOX_GROUP"],
    )

    sandbox = None
    try:
        print("==> Booting sandbox (async)...")
        poller = await client.begin_create_sandbox(labels={"guide": "async"})
        sandbox = await poller.result()
        print(f"    sandbox: {sandbox.sandbox_id}")

        # Each command sleeps ~1s server-side, so 5 sequential ≈ 5s,
        # 5 concurrent ≈ 1s + overhead. This makes the speedup obvious.
        cmds = [
            "sleep 1; echo hostname: $(hostname)",
            "sleep 1; echo uptime: $(uptime -p)",
            "sleep 1; echo kernel: $(uname -r)",
            "sleep 1; echo cpus: $(nproc)",
            "sleep 1; echo memory: $(free -h | head -2 | tail -1)",
        ]

        print(f"\n==> asyncio.gather over {len(cmds)} concurrent exec calls...")
        t0 = time.perf_counter()
        results = await asyncio.gather(*(sandbox.exec(c) for c in cmds))
        wall = time.perf_counter() - t0
        for r in results:
            print(f"    {r.stdout.strip()}")
        print(f"\n==> concurrent wall: {wall:.2f}s for {len(cmds)} calls")

        print("\n==> Same calls sequentially for comparison...")
        t0 = time.perf_counter()
        for c in cmds:
            await sandbox.exec(c)
        seq = time.perf_counter() - t0
        print(f"    sequential wall: {seq:.2f}s")

        if wall > 0:
            print(f"\n==> Speedup: {seq / wall:.1f}x")
    finally:
        if sandbox is not None:
            print(f"\n==> Deleting sandbox {sandbox.sandbox_id}...")
            try:
                await sandbox.delete()
            except Exception:
                pass
        await client.close()
        await credential.close()


if __name__ == "__main__":
    asyncio.run(main())
