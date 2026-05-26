# OpenAI computer-use in an ACA sandbox

Drives an Azure OpenAI `computer-use-preview` deployment against a Linux
desktop running inside an Azure Container Apps sandbox using the
[**OpenAI Agents SDK**](https://github.com/openai/openai-agents-python)
(`ComputerTool` + `AsyncComputer`). The agent fills out a multi-field
expense-report form end to end — you watch it work in your browser via
noVNC.

See the parent [`README.md`](../README.md) for the scenario overview and
why a sandbox is the right runtime.

## What runs where

```
┌─────────────────── your laptop ─────────────────────┐
│                                                     │
│  python/computer_use.py                             │
│   Agent(tools=[ComputerTool(ACAAsyncComputer(...))])│
│      └─ OpenAIResponsesModel(AsyncAzureOpenAI(...)) │  ──► Azure OpenAI
│                              │                      │      (computer-use-
│                              │ HTTPS                │       preview)
└──────────────────────────────┼──────────────────────┘
                               │ HTTPS (add_port(7000))
                               ▼
┌──────────────── ACA sandbox (ephemeral) ────────────┐
│  Xvfb :99  ─►  Chrome  ─►  http://localhost:8080/   │  ◄── what the
│       ▲                              (demo form)    │      agent sees
│       │                                             │
│  control_server.py (FastAPI, :7000)                 │  ◄── screenshot /
│       └─ xdotool, scrot                             │      click / type ...
│                                                     │
│  x11vnc :5900 ─► noVNC :6080  ─────►  your browser  │  ◄── watch live
│                              (add_port(6080))       │
└─────────────────────────────────────────────────────┘
```

- The **agent loop** runs on your laptop. `Runner.run` calls the
  Responses API, the model emits `computer_call` items, the Agents SDK
  invokes the matching method on our `ACAAsyncComputer`, which POSTs
  to the in-sandbox control server.
- The **desktop** runs in the sandbox. The only thing the agent perceives
  is the screenshot stream; the only thing it can do is click/type/scroll
  via the control server.
- The sandbox runs with **deny-by-default egress and no allow rules** —
  it literally cannot reach the internet. The demo target is the form
  served at `localhost:8080` *inside* the same sandbox.

## Prerequisites

1. The shared sandbox baseline:
   ```bash
   cd samples/sandboxes/setup/python
   pip install -r requirements.txt
   python setup.py
   ```
2. An **Azure OpenAI** resource with a `computer-use-preview` deployment.
   - The model is gated preview, available in `eastus2` and
     `swedencentral`. Request access at <https://aka.ms/oai/cu>.
   - Create the deployment in the Azure portal (or `az cognitiveservices
     account deployment create ...`), then note the deployment name.

## Configure

Add to `samples/.env` (or your shell):

```
AZURE_OPENAI_ENDPOINT=https://<your-aoai>.openai.azure.com/
AZURE_OPENAI_API_KEY=<key>
AZURE_OPENAI_COMPUTER_USE_DEPLOYMENT=<deployment-name>
# Optional. Defaults to 2025-04-01-preview.
# AZURE_OPENAI_API_VERSION=2025-04-01-preview
```

The sandbox-group variables (`AZURE_SUBSCRIPTION_ID`, `ACA_RESOURCE_GROUP`,
`ACA_SANDBOX_GROUP`, `ACA_SANDBOXGROUP_REGION`) are already there from
`setup.py`.

## Run

```bash
cd samples/sandboxes/scenarios/07-computer-use/openai/python
pip install -r requirements.txt
python computer_use.py
```

To bring up the desktop and drive it yourself (skip the LLM entirely —
useful for testing the platform or for live demos before the model is
deployed):

```bash
python computer_use.py --manual
```

What you'll see in `--manual` mode:

```
==> Booting sandbox (run=a1b2c3d4)...
    sandbox: 72da4522-...
==> Uploading desktop image from .../desktop-image...
==> Running setup.sh (~2-4 min: apt installs Chrome + noVNC + ...)...
desktop ready
==> Exposing ports...
    control : https://72da4522-...--7000.westus2.adcproxy.io
    noVNC   : https://72da4522-...--6080.westus2.adcproxy.io
==> Locking sandbox egress (deny-by-default)...

============================================================================
  --manual: no AI loop. Open this URL in your browser:

    https://72da4522-...--6080.westus2.adcproxy.io/vnc.html?autoconnect=1&resize=remote
============================================================================
```

In agent mode you'll additionally see `Runner.run` driving the model
through screenshot → click → type → keypress turns until the form
submits, followed by the verified `/tmp/submission.json`.

## Files

| File | What it does |
|---|---|
| [`computer_use.py`](python/computer_use.py) | End-to-end: boot sandbox, install desktop, expose ports, build the `Agent`, run with `Runner.run`, verify, delete. `--manual` skips the agent. |
| [`aca_computer.py`](python/aca_computer.py) | `ACAAsyncComputer(AsyncComputer)` — translates each Agents-SDK call (`click`, `type`, `screenshot`, ...) into an HTTP call against the in-sandbox control server. |
| `requirements.txt` | Pulls `openai`, `openai-agents`, `httpx`, and the shared `azure-containerapps-sandbox` wheel. |

The desktop itself (`Xvfb` + Chrome + `xdotool` + noVNC + the FastAPI
control server + the demo form) lives one level up, in
[`../desktop-image/`](../desktop-image/), so it can be shared with future
vendors.

## Adapting the demo

- **Drive a real website.** Change `TASK_PROMPT` in `computer_use.py` and
  swap the Chrome `--app=http://localhost:8080/` flag in `setup.sh` to
  the target URL. Then keep egress open or add an allow rule for the
  target's hostname (omit the `set_egress_default("Deny")` line, or
  follow it with `sandbox.add_egress_host_rule("*.example.com", action="Allow")`).
- **Change the screen size.** Update `DISPLAY_W`/`DISPLAY_H` in
  `computer_use.py` *and* the `Xvfb :99 -screen 0 1280x800x24` line in
  `setup.sh`.
- **Persist the desktop.** After `setup.sh` finishes once, `begin_commit`
  the sandbox to a disk (see [guide 03](../../../guides/03-disks)) and
  reboot from `disk_id=` next time. Drops setup from ~3 min to ~10 sec.

## Troubleshooting

- **`DeploymentNotFound`** — there is no `computer-use-preview`
  deployment on the AOAI resource that `AZURE_OPENAI_ENDPOINT` points
  to, or your `AZURE_OPENAI_COMPUTER_USE_DEPLOYMENT` name is wrong.
  Create it in the portal under the AOAI resource's Deployments tab.
- **`control server never became ready`** — the public port is taking
  longer than expected to wire up. Check the sandbox logs via a quick
  `sandbox.exec("tail -n 50 /var/log/desktop/control.log")` from a
  separate script.
- **Agent keeps clicking the wrong spot** — the dimensions the tool
  reports (`AsyncComputer.dimensions`) must match what Xvfb is actually
  serving. If you change one, change both.
- **`no /tmp/submission.json`** — the agent gave up before clicking
  Submit. Re-run with the noVNC tab open to see where it got stuck.
  Increase `MAX_AGENT_TURNS` if it ran out, or simplify the prompt if it
  looped.

## Reference

- Azure OpenAI computer use — <https://learn.microsoft.com/azure/ai-services/openai/how-to/computer-use>
- OpenAI Agents SDK — <https://github.com/openai/openai-agents-python>
- OpenAI Responses API computer-use tool — <https://platform.openai.com/docs/guides/tools-computer-use>
- Daytona cookbook (same pattern, different sandbox) — <https://github.com/openai/openai-cookbook/blob/main/examples/agents_sdk/computer_use_with_daytona/computer_use_with_daytona.ipynb>
