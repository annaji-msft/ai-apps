# Sandbox scenarios

Composed use cases that combine multiple sandbox capabilities. Every
scenario here is runnable today — `cd` into one, install its
`requirements.txt`, run.

| # | Scenario | What it shows | Status |
|---|---|---|---|
| 01 | [webapps](01-webapps) | Run a web app in a sandbox; patterns include `simple-anonymous` (open to the internet) and (planned) `authenticated` (Entra-gated) | ✅ ready |
| 02 | [coding-agents](02-coding-agents) | Run **Copilot CLI** in a sandbox with deny-default egress + portal-paste PAT injection (Python + CLI). Claude Code / Codex stubs included. | ✅ Copilot CLI ready |
| 03 | [code-interpreter](03-code-interpreter) | LLM-driven code execution — generate, run, observe, iterate. `openai/` (Azure OpenAI + tool calling, sales CSV, plot retrieval) | ✅ Azure OpenAI ready |
| 04 | [swarms](04-swarms) | Many sandboxes, one orchestrator — fan-out work across N workers (`sandbox-inception`, `shared-blob-memory`) | ✅ ready |
| 05 | [data-processing](05-data-processing) | Producer/consumer pipeline on a shared AzureBlob volume — producer streams batches, transformer enriches concurrently, aggregator summarises. Pure-stdlib workers. | ✅ Python ready · 📝 CLI planned |
| 06 | [developer-workflows](06-developer-workflows) | Ephemeral CI runner — cold-boot + snapshot the warm runner, then build N PRs in parallel from the snapshot. Ships 3 synthetic PRs that exercise both pass and fail paths. | ✅ Python ready |
| 07 | [computer-use](07-computer-use) | LLM computer-use agent (Azure OpenAI `computer-use-preview`) driving Chromium inside a sandbox to fill out a form; watch live via noVNC | ✅ OpenAI ready |
| 08 | [sandbox-agents](08-sandbox-agents) | Wire agent frameworks (OpenAI Agents SDK, LangChain, Anthropic) to a sandbox as their tool-execution environment | ✅ ready |
| 09 | [mcp-hosting](09-mcp-hosting) | Host **Model Context Protocol (MCP)** servers in sandboxes (`excalidraw-anonymous`, `dab-sql-devtunnel`) for AI clients to connect over HTTPS | ✅ ready |
| 10 | [connectors-triggers](10-connectors-triggers) | Connector-gateway **triggers** push outside events (Office 365 / SharePoint / OneDrive / …) into a sandbox webhook. Includes a lifecycle walk-through and a round-trip Office 365 → sandbox → Office 365 reply scenario with minimal stdlib processing. | ✅ ready |
