# AI Gateway

> Status: coming soon.

Front-door for AI traffic into Azure Container Apps — model routing,
rate limiting, key management, observability, and cost controls in
front of LLM endpoints (Azure OpenAI, OpenAI, Anthropic, custom
self-hosted models running in `containerapps/` or `sandboxes/`).

Will follow the same shape as [`sandboxes/`](../sandboxes/README.md):
`setup/`, `guides/NN-*`, and `scenarios/*`.

Planned guides: getting-started, multi-model routing, rate limits,
key vault integration, request/response logging, prompt-cost tracking,
caching, fallback chains.

Planned scenarios: hardened-llm-frontend, multi-tenant-model-routing,
cost-capped-chat, model-AB-testing.
