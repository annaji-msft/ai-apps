# Scenario — email → sandbox → AI-composed reply (CLI)

Bash version of `../python/run.py`. Same end-to-end flow: create a
sandbox on the [`copilot` disk image](https://learn.microsoft.com/azure/container-apps/sandbox-disk-images)
with `gatewayConnections=[{ resourceId }]` so the platform proxy
injects the Bearer for outbound calls to the Office 365 connection,
deploy the listener from `../app/server.py`, lock egress down (Deny +
GitHub host-Allow only), add port 5000 gated by the gateway MI, and
create an `OnNewEmailV3` trigger config with `subjectFilter=Feedback`.

Each incoming feedback email is composed into a personalized reply
by the pre-installed `copilot` CLI and sent back via `SendMailV2`
on the **same** connection. See [`../README.md`](../README.md) for
the GitHub-token prerequisite (the script reads
`COPILOT_GITHUB_TOKEN`/`GH_TOKEN`/`GITHUB_TOKEN`, then falls back
to `gh auth token`, then prompts).

## Prerequisites

- Both prerequisites applied (sandboxes baseline + connector-gateway
  setup) (`samples/sandboxes/setup/cli/setup.sh` and
  `samples/sandboxes/scenarios/10-connectors-triggers/setup/cli/setup.sh`).
- `az login` and `aca` on `PATH`.
- `python3` on `PATH`. The script shells out to short inline `python3`
  snippets for sandbox-create-body assembly and JSON parsing of the
  dataplane PUT response (the Python SDK does not yet expose
  `gateway_connections` on `begin_create_sandbox`, so the CLI flow hits
  the dataplane directly).
- A GitHub token usable by the Copilot CLI (see scenario README).
- Optional: `TRIAGE_RECIPIENT` in `samples/.env`. Defaults to
  `ACA_USER_EMAIL` (the consenting user).

## Run

```bash
./run.sh
```

When the prompt appears, send yourself (or the user listed as
`TRIAGE_RECIPIENT`) an email whose subject contains **Feedback**.
Within ~1 minute you should receive a follow-up email with subject
`Auto-ack: received your message`.

Tail listener logs from another terminal:

```bash
aca sandbox exec -g "$ACA_RESOURCE_GROUP" --group "$ACA_SANDBOX_GROUP" \
  --id <sandbox-id> --command 'tail -f /tmp/listener.log'
```

Press Enter when done — cleanup is automatic (trigger → port →
sandbox; gateway + connection are kept).
