"""Parallel fan-out — run the same task on N sandboxes concurrently.

Uses the async SDK (`azure.containerapps.sandbox.aio`) + asyncio.gather
so all N sandbox lifecycles overlap. With N workers and per-sandbox
time T, wall-clock stays ~T instead of N*T.

Reads configuration from samples/.env (written by samples/sandboxes/setup/setup.py).
"""

from __future__ import annotations

import asyncio
import json
import os
import time
from pathlib import Path

from azure.identity.aio import DefaultAzureCredential
from azure.containerapps.sandbox import endpoint_for_region
from azure.containerapps.sandbox.aio import SandboxGroupClient


WORKER_SCRIPT = """\
import json, os
n = int(os.environ["ITEM"])
result = {"input": n, "output": n * n, "host": os.uname().nodename}
with open("/tmp/result.json", "w") as f:
    json.dump(result, f)
print(json.dumps(result))
"""


def _load_env() -> None:
    for parent in Path(__file__).resolve().parents:
        env = parent / ".env"
        if env.is_file():
            for line in env.read_text().splitlines():
                if line and not line.startswith("#") and "=" in line:
                    k, v = line.split("=", 1)
                    os.environ.setdefault(k.strip(), v.strip())
            return


async def process_item(client: SandboxGroupClient, item: int, index: int) -> dict:
    """Boot a sandbox, run the worker script with ITEM=<item>, collect result, tear down."""
    sandbox = None
    started = time.perf_counter()
    payload: dict = {"input": item}
    try:
        print(f"  [{index}] booting sandbox for item={item}...")
        poller = await client.begin_create_sandbox(
            labels={"role": "fan-out-worker", "index": str(index)},
        )
        sandbox = await poller.result()

        await sandbox.write_file("/tmp/worker.py", WORKER_SCRIPT.encode())
        exec_result = await sandbox.exec(f"ITEM={item} python3 /tmp/worker.py")
        if exec_result.exit_code != 0:
            raise RuntimeError(f"worker {index} failed: {exec_result.stderr}")

        raw = await sandbox.read_file("/tmp/result.json")
        text = raw.decode() if isinstance(raw, (bytes, bytearray)) else raw
        payload.update(json.loads(text))
        return payload
    finally:
        if sandbox is not None:
            try:
                await sandbox.delete()
            except Exception:
                pass
        payload["_elapsed"] = time.perf_counter() - started
        print(f"  [{index}] item={item} took {payload['_elapsed']:.1f}s end-to-end")


async def main() -> None:
    _load_env()
    num_workers = int(os.environ.get("NUM_WORKERS", "4"))
    items = list(range(1, num_workers + 1))

    credential = DefaultAzureCredential()
    client = SandboxGroupClient(
        endpoint_for_region(os.environ["ACA_SANDBOXGROUP_REGION"]),
        credential,
        subscription_id=os.environ["AZURE_SUBSCRIPTION_ID"],
        resource_group=os.environ["ACA_RESOURCE_GROUP"],
        sandbox_group=os.environ["ACA_SANDBOX_GROUP"],
    )

    try:
        print(f"==> Fanning out {num_workers} sandboxes in parallel...")
        wall_start = time.perf_counter()
        results = await asyncio.gather(
            *(process_item(client, item, i) for i, item in enumerate(items)),
            return_exceptions=True,
        )
        wall_elapsed = time.perf_counter() - wall_start

        print("\n==> Results:")
        successes, failures = [], []
        for i, r in enumerate(results):
            if isinstance(r, Exception):
                failures.append((items[i], r))
                print(f"  item={items[i]}  FAILED: {r}")
            else:
                successes.append(r)
                print(f"  item={r['input']}  ->  {r['output']}  (host={r['host'][:12]}...)")

        per_item_total = sum(r.get("_elapsed", 0.0) for r in successes)
        speedup = (per_item_total / wall_elapsed) if wall_elapsed > 0 else 0.0
        print(
            f"\n==> Wall clock: {wall_elapsed:.1f}s for {num_workers} items "
            f"(sequential would have taken ~{per_item_total:.0f}s; speedup ~{speedup:.1f}x)"
        )
        if failures:
            print(f"==> {len(failures)} failure(s); {len(successes)} success(es).")
    finally:
        await client.close()
        await credential.close()


if __name__ == "__main__":
    asyncio.run(main())
