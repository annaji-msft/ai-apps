"""Agent swarm — orchestrator dispatches mapper + reducer roles.

Mappers (N, parallel) count words in their chunk; reducer aggregates
all mapper output into top-K words. Swap the worker scripts for any
real per-role logic (LLM calls, code execution, tool use).

Reads configuration from samples/.env (written by samples/sandboxes/setup/setup.py).
"""

from __future__ import annotations

import asyncio
import json
import os
from pathlib import Path

from azure.identity.aio import DefaultAzureCredential
from azure.containerapps.sandbox import endpoint_for_region
from azure.containerapps.sandbox.aio import SandboxGroupClient


CORPUS = """\
the quick brown fox jumps over the lazy dog
the dog barks and the fox runs the fox is quick
brown dogs and quick foxes are common in stories
the lazy cat watches the quick brown fox jump again
"""

MAPPER_SCRIPT = """\
import json, collections, sys
text = open("/tmp/chunk.txt").read()
counts = collections.Counter(text.split())
with open("/tmp/mapper_out.json", "w") as f:
    json.dump(dict(counts), f)
print("mapped", len(counts), "unique words")
"""

REDUCER_SCRIPT = """\
import json, collections, glob
total = collections.Counter()
for path in sorted(glob.glob("/tmp/mapper_*.json")):
    with open(path) as f:
        total.update(json.load(f))
top = total.most_common(10)
with open("/tmp/reducer_out.json", "w") as f:
    json.dump(top, f)
print("reduced", len(total), "unique words")
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


def _chunks(text: str, n: int) -> list[str]:
    lines = [ln for ln in text.splitlines() if ln.strip()]
    out: list[list[str]] = [[] for _ in range(n)]
    for i, ln in enumerate(lines):
        out[i % n].append(ln)
    return ["\n".join(c) for c in out if c]


async def run_mapper(client: SandboxGroupClient, index: int, chunk: str) -> dict[str, int]:
    sandbox = None
    try:
        print(f"  mapper[{index}] booting...")
        poller = await client.begin_create_sandbox(
            labels={"role": "mapper", "index": str(index)},
        )
        sandbox = await poller.result()
        await sandbox.write_file("/tmp/chunk.txt", chunk.encode())
        await sandbox.write_file("/tmp/mapper.py", MAPPER_SCRIPT.encode())
        result = await sandbox.exec("python3 /tmp/mapper.py")
        if result.exit_code != 0:
            raise RuntimeError(f"mapper {index} failed: {result.stderr}")
        raw = await sandbox.read_file("/tmp/mapper_out.json")
        text = raw.decode() if isinstance(raw, (bytes, bytearray)) else raw
        counts = json.loads(text)
        print(f"  mapper[{index}] -> {len(counts)} unique words")
        return counts
    finally:
        if sandbox is not None:
            try:
                await sandbox.delete()
            except Exception:
                pass


async def run_reducer(client: SandboxGroupClient, mapper_outputs: list[dict[str, int]]) -> list[tuple[str, int]]:
    sandbox = None
    try:
        print("  reducer booting...")
        poller = await client.begin_create_sandbox(labels={"role": "reducer"})
        sandbox = await poller.result()
        for i, m in enumerate(mapper_outputs):
            await sandbox.write_file(f"/tmp/mapper_{i:03d}.json", json.dumps(m).encode())
        await sandbox.write_file("/tmp/reducer.py", REDUCER_SCRIPT.encode())
        result = await sandbox.exec("python3 /tmp/reducer.py")
        if result.exit_code != 0:
            raise RuntimeError(f"reducer failed: {result.stderr}")
        raw = await sandbox.read_file("/tmp/reducer_out.json")
        text = raw.decode() if isinstance(raw, (bytes, bytearray)) else raw
        return [(w, c) for w, c in json.loads(text)]
    finally:
        if sandbox is not None:
            try:
                await sandbox.delete()
            except Exception:
                pass


async def main() -> None:
    _load_env()
    n = int(os.environ.get("NUM_MAPPERS", "3"))
    chunks = _chunks(CORPUS, n)

    credential = DefaultAzureCredential()
    client = SandboxGroupClient(
        endpoint_for_region(os.environ["ACA_SANDBOXGROUP_REGION"]),
        credential,
        subscription_id=os.environ["AZURE_SUBSCRIPTION_ID"],
        resource_group=os.environ["ACA_RESOURCE_GROUP"],
        sandbox_group=os.environ["ACA_SANDBOX_GROUP"],
    )

    try:
        print(f"==> Map phase: dispatching {len(chunks)} mappers in parallel...")
        mapper_results = await asyncio.gather(
            *(run_mapper(client, i, c) for i, c in enumerate(chunks))
        )

        print("\n==> Reduce phase: aggregating...")
        top = await run_reducer(client, mapper_results)

        print("\n==> Top-10 words:")
        for word, count in top:
            print(f"  {count:>3}  {word}")
    finally:
        await client.close()
        await credential.close()


if __name__ == "__main__":
    asyncio.run(main())
