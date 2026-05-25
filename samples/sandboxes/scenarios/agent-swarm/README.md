# Scenario: Agent swarm

A simple **orchestrator → workers** pattern: an orchestrator coroutine
dispatches different *roles* to a swarm of sandboxes and combines
their output. This is the shape behind real multi-agent systems
(researcher + summarizer, planner + executors, mapper + reducer).

- [`python/`](python/) — Python async SDK (`azure.containerapps.sandbox.aio`)

> No CLI variant: agent swarms are coordination logic; that lives in
> code, not shell.

## The pattern

```
orchestrator
   ├── spawn N mapper sandboxes (in parallel) → each emits partial result
   └── spawn 1 reducer sandbox → consumes mappers' output → final answer
```

We use a word-count toy: mappers each count words in a chunk of text,
the reducer sums the per-word counts. Swap the scripts for any real
task (LLM call, code execution, tool use).

## What it does

1. Split a fixed corpus into N chunks
2. Fan out N **mapper** sandboxes in parallel (`asyncio.gather`)
   - Each runs a Python script that counts words in its chunk
   - Returns `{word: count}` JSON
3. Spin up 1 **reducer** sandbox
   - Receives all mapper outputs, sums per-word counts
   - Returns the top-10 words
4. Print the final ranked list

## Production tips

- **Don't put agent business-logic in the orchestrator.** Each sandbox
  should be a small, replaceable unit. The orchestrator only knows
  *how to dispatch*, not *what each worker does* — that's in the
  worker script (or the prompt you ship to an LLM-driven worker).
- **Pass inputs as files, return outputs as files.** `write_file` +
  `read_file` is more reliable than embedding payloads in `exec`
  arguments — no shell-escaping headaches with large or binary data.
- **Snapshot the worker image once.** If every mapper installs the
  same packages, snapshot a primed sandbox ([guide 04](../../guides/04-snapshots))
  and have mappers boot from the snapshot. Skips per-task setup.
- **Coordination via blob is more robust than via the orchestrator.**
  For real swarms (mappers + reducers running on different schedules),
  mount an AzureBlob volume so mappers `PUT` results and the reducer
  `LIST` + `GET`s them. Phase 3 guide 07.
- **For *true* inception** — agents spawning agents in a separate
  isolation domain — use the **two-sandbox-group + Managed Identity**
  pattern: orchestrator group has a SystemAssigned MI granted Data
  Owner on the worker group. That recipe lands in Phase 3.
