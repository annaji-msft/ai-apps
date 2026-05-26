# MI inception swarm — `aca` CLI variant

Same scenario as the Python variant, but the orchestration is bash +
the `aca` CLI. The script is structured so that **`aca config`** is
the obvious ergonomic win — neither the host nor the orchestrator pass
`--subscription` / `--resource-group` / `--group` / `--managed-identity`
on individual `aca` calls.

```bash
./run.sh
```

Configuration is read from `samples/.env` (run [`../../../../setup`](../../../../setup)
once if you haven't).

The full scenario story (architecture diagram, four customer-value
claims, production tips) lives in [`../README.md`](../README.md).
