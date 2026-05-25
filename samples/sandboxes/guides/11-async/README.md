# Guide 11 — Async SDK

The async sibling of `azure.containerapps.sandbox` lives at
`azure.containerapps.sandbox.aio`. Same surface, all coroutines —
plug it into `asyncio.gather` for free concurrency.

- [`python/`](python/) — `from azure.containerapps.sandbox.aio import SandboxGroupClient`

> No CLI variant: this is a Python concurrency feature.

## What's covered

| Sync | Async |
|---|---|
| `from azure.containerapps.sandbox import SandboxGroupClient` | `from azure.containerapps.sandbox.aio import SandboxGroupClient` |
| `from azure.identity import DefaultAzureCredential` | `from azure.identity.aio import DefaultAzureCredential` |
| `client.begin_create_sandbox().result()` | `(await client.begin_create_sandbox()).result()` returning awaitable |
| `sandbox.exec("...")` | `await sandbox.exec("...")` |
| `asyncio.gather(*ops)` to run many in parallel | same |

## Demo flow

1. Boot a single sandbox (async)
2. `asyncio.gather` of 5 `exec` calls — they all run concurrently
3. Compare total wall time to sequential
4. Tear down

## Why this matters

- A single sandbox can serve many concurrent operations.
- A single orchestrator can drive many sandboxes in parallel
  (see [`scenarios/parallel-fan-out`](../../scenarios/parallel-fan-out)
  and [`scenarios/agent-swarm`](../../scenarios/agent-swarm)).
- Always `await client.close()` and `await credential.close()` to release
  connection pools.
