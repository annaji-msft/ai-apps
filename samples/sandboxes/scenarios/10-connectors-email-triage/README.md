# 10-connectors-email-triage — Email-triggered Copilot in a sandbox

> **Status:** in progress. Wires Azure **Connector Gateway** (preview,
> `Microsoft.Web/connectorGateways`, `2026-05-01-preview`) into the
> sandbox-per-event pattern so a fresh ACA sandbox runs **Copilot CLI**
> on every new Outlook email, posts a triage card to Teams via the
> gateway's **Managed MCP server**, and never holds a credential —
> the egress proxy stamps the MCP API key onto outbound requests at
> the boundary.

Composes [`scenarios/02-coding-agents/gh-copilot-cli`](../02-coding-agents/gh-copilot-cli)
(Copilot CLI + egress-proxy credential mediation pattern) and
[`guides/08-egress`](../../guides/08-egress) (deny-default + Transform
rules).

## What this ships

```
10-connectors-email-triage/
├── README.md                  (this file — architecture, run, prod tips)
├── azure.yaml                 (azd entrypoint)
├── infra/
│   ├── main.bicep
│   ├── modules/               (one .bicep per Azure resource)
│   │   ├── connector-gateway.bicep
│   │   ├── connection-office365.bicep
│   │   ├── connection-teams.bicep
│   │   ├── mcpserver-teams.bicep
│   │   ├── trigger-on-new-email.bicep
│   │   ├── sandbox-group.bicep
│   │   ├── egress-policy.bicep
│   │   └── receiver.bicep     (ACA env + receiver container app)
│   └── scripts/
│       ├── postdeploy.sh      (fetch API key, patch egress, print consent)
│       └── postdeploy.ps1
├── receiver/                  (Python ACA app — webhook handler)
│   ├── app.py
│   ├── requirements.txt
│   └── Dockerfile
├── prompts/
│   └── triage.md              (Copilot CLI prompt template)
└── python/                    (local-dev runner — no azd needed)
    ├── README.md
    ├── requirements.txt
    ├── run.py                 (boot a sandbox by hand with a sample email)
    └── samples/sample-email.json
```

## Cloud-deployed quickstart (`azd up`)

```bash
cd samples/sandboxes/scenarios/10-connectors-email-triage
azd up
```

The post-deploy hook prints OAuth consent URLs for the Office 365 and
Teams connections — open each once in a browser tab, sign in with the
account whose mailbox / Teams channel you want the triage flow to use.
After that, send an email to that mailbox and watch the triage card
arrive in Teams.

## Local-dev quickstart (no `azd up`)

The `python/run.py` runner boots a sandbox manually with a sample
email payload, runs the same Copilot CLI flow, and points at any
MCP endpoint you give it (your own gateway from `azd up`, or a
shared dev gateway). Useful for iterating on the Copilot prompt
without redeploying.

```bash
cd python
pip install -r requirements.txt
python run.py --email samples/sample-email.json
```

See [`python/README.md`](python/README.md) for full options.

## Architecture, prerequisites, production tips

_Filled in as the build progresses._
