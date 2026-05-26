# AI app workloads

> Status: coming in Phase 8.

Real-world scenarios composing two or more pillars (sandboxes + containerapps +
connectors + triggers + ai-gateway). Each scenario declares its pillar
dependencies at the top of its README.

Planned scenarios:

- **copilot-coding-agent** - apps (orchestrator) + sandboxes (per-task
  isolation) + connectors (Cosmos for state) + triggers (HTTP webhook)
- **research-agent-swarm** - trigger HTTP -> app orchestrator -> N parallel
  sandboxes -> connector (Azure Storage + Azure OpenAI)
- **doc-processing-pipeline** - trigger Blob/EventGrid -> app router ->
  sandbox parser -> connector (Cosmos for index, Azure OpenAI for embeddings)
- **ai-data-engineer** - trigger cron -> job (ETL) -> sandbox (notebook) ->
  connector (Postgres + Storage)
- **autonomous-code-reviewer** - trigger GitHub webhook -> app router ->
  per-PR sandbox + connector (Key Vault for tokens)
- **multi-tenant-agent-runtime** - per-tenant app + per-tenant sandbox pool
  + per-tenant connector bindings
