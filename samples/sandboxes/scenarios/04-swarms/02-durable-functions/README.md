# 02 — Durable functions (planned)

> **Coming soon.** This swarm variant is a placeholder. Track progress
> in [samples/sandboxes/README.md](../../../README.md).

A durable, retry-safe alternative to the in-sandbox
[`01-mi-inception`](../01-mi-inception) variant. The orchestrator is an
**Azure Functions app** bound to **Durable Task Scheduler (DTS)**:

- The orchestrator function runs a DTS *orchestration*; activity
  functions create sandboxes (one activity per work item) and a
  fan-in activity gathers results.
- DTS provides history, replay-on-failure, distributed locks,
  long-running orchestrations, sub-orchestrations, and full portal
  observability — none of which the in-sandbox `asyncio.gather`
  variant has.
- Identity story is unchanged: the Functions app's MI is granted
  `Container Apps SandboxGroup Data Owner` on the sandbox group that
  hosts the worker sandboxes. No credentials in code.

**Pick this variant when** work items take minutes-to-hours, partial
failures should resume instead of restart, the swarm needs to be
triggered by HTTP / queue / timer rather than by a human, or you want
the orchestration's progress and history visible in the Azure portal.

**Pick [`01-mi-inception`](../01-mi-inception) instead when** the
orchestrator is itself an LLM agent inside a sandbox, the swarm is
short-lived (seconds-to-minutes), and you want zero extra
infrastructure to operate.
