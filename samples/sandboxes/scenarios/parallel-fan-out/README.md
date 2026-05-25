# Scenario: Parallel fan-out

Run the same task across **N sandboxes concurrently** using the async
SDK + `asyncio.gather`. Each sandbox processes one input item and
returns its result; the orchestrator aggregates everything at the end.

This is the classic embarrassingly-parallel pattern for AI workloads:
batch inference, parallel code execution, per-row data transforms.

- [`python/`](python/) — Python async SDK (`azure.containerapps.sandbox.aio`)

> No CLI variant: the value here is `asyncio.gather` over many
> concurrent sandbox lifecycles, which doesn't map cleanly to shell.

## What it does

1. Take a list of N input items (here: numbers 1..N)
2. `asyncio.gather` — for each item, in parallel:
   - Create a sandbox
   - Upload + execute a worker script with the item as input
   - Read the result file back
   - Delete the sandbox
3. Print all collected results and the total wall-clock time

## Why this matters

The naive sequential version takes `N × per-sandbox-time`. The parallel
version takes `≈ per-sandbox-time` (plus a bit of overhead) — N can be
50, 500, or 5000 and the total time barely moves. The aio SDK + asyncio
gives you that scale-out for free.

## Production tips

- **Cap concurrency with a semaphore** if N is large. Each sandbox is a
  full VM and your subscription has per-region quotas. Wrap the per-item
  coroutine in `async with sem:` to keep ≤K in flight.
- **Retry transient failures per-item, not the whole batch.** A single
  sandbox boot failure shouldn't kill 999 successful jobs. Wrap each
  task with try/except and collect failures separately.
- **Always clean up in `finally`.** `asyncio.gather(..., return_exceptions=True)`
  lets you collect results without short-circuiting, but you still need
  a `finally` per task to delete sandboxes even when work fails.
- **Use snapshots for warm starts.** If every worker needs the same
  packages or model weights, snapshot a primed sandbox once
  ([guide 04](../../guides/04-snapshots)) and boot workers from
  `disk=snapshot-name` to skip per-task setup.
- **Stream results, don't accumulate in memory.** For long-running
  batches, write each result to blob storage (volumes — Phase 3 guide
  07) instead of holding `List[Result]` in the orchestrator.
