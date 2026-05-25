# Samples

Runnable samples for AI-native applications on Azure Container Apps.

## How this catalog is organized

Five pillars, same shape inside each:

```
samples/
  sandboxes/         apps/         connectors/         triggers/         ai-app-workloads/
    setup/             setup/        setup/              setup/            (composes other pillars)
    guides/            guides/       guides/             guides/
    scenarios/         scenarios/    scenarios/          scenarios/
```

- **`setup/`** — one Python script per pillar. Run it once. Provisions the
  baseline Azure resources that pillar needs and writes the resulting
  configuration to `samples/.env`.
- **`guides/NN-*`** — focused, one-capability-per-script samples (~50 lines).
  Numbered for reading order.
- **`scenarios/*`** — composed end-to-end use cases. Each scenario has a
  narrative README, working code in Python and CLI variants, and a
  "Production tips" section. Integrations with third-party agents (Claude
  Code, OpenAI Codex, GitHub Copilot CLI, LangChain, AutoGen, etc.) live
  here too — they're just scenarios that happen to wrap an external agent.

## Quickstart

See the [repo root README](../README.md#quickstart).

## Pillars

| Pillar | Purpose | Status |
|---|---|---|
| [`sandboxes/`](sandboxes) | Isolated, on-demand VMs for AI agents and code execution | Setup ready · Guides in progress |
| [`apps/`](apps) | Long-running container apps and container apps jobs | Coming soon |
| [`connectors/`](connectors) | Managed service connector bindings | Coming soon |
| [`triggers/`](triggers) | HTTP / event / scheduled / KEDA triggers | Coming soon |
| [`ai-app-workloads/`](ai-app-workloads) | Cross-pillar real-world scenarios | Coming soon |

## Conventions

- **Authentication**: every sample uses `DefaultAzureCredential`. Run `az login`
  once before running any sample.
- **Configuration**: every sample reads `samples/.env` (created by the
  appropriate `setup/` script). See [`.env.example`](.env.example) for the
  full list of variables.
- **Dependencies**: every sample has its own `requirements.txt` so
  `pip install -r requirements.txt` from inside the sample folder always
  works. The root [`requirements.txt`](requirements.txt) holds the shared
  baseline (ACA SDK + `azure-identity`).
- **Cleanup**: every sample deletes only what it created. To remove the
  shared baseline infra, run the pillar's `setup/teardown.py`.
