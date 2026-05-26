# OpenAI computer-use in an ACA sandbox

Drives an Azure OpenAI `computer-use-preview` deployment against a Linux
desktop running inside an Azure Container Apps sandbox. The agent fills out
a multi-field expense-report form end to end — you watch it work in your
browser via noVNC.

See the parent [`README.md`](../README.md) for the scenario overview and
why a sandbox is the right runtime.

## What runs where

```
┌─────────────────── your laptop ─────────────────────┐
│                                                     │
│   python/computer_use.py                            │
│      ├─ AzureOpenAI(...).responses.create(...)      │  ──► Azure OpenAI
│      └─ ACAComputer(base_url=https://...port-7000)  │  ──► sandbox
│                                                     │
└─────────────────────────────────────────────────────┘
                              │
                              │ HTTPS  (add_port(7000))
                              ▼
┌──────────────── ACA sandbox (ephemeral) ────────────┐
│  Xvfb :99  ─►  Chromium ─►  http://localhost:8080/  │  ◄── what the
│       ▲                              (demo form)    │      agent sees
│       │                                             │
│  control_server.py (FastAPI, :7000)                 │  ◄── screenshot /
│       └─ xdotool, scrot                             │      click / type ...
│                                                     │
│  x11vnc :5900 ─► noVNC :6080  ─────►  your browser  │  ◄── watch live
│                              (add_port(6080))       │
└─────────────────────────────────────────────────────┘
```

- The **agent loop** runs on your laptop. It calls the Responses API,
  receives `computer_call` items, executes them, and sends back a fresh
  screenshot as the call output.
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
   The model is gated — request access at <https://aka.ms/oai/cu> if you
   don't have it yet.

## Configure

Add to `samples/.env` (or your shell):

```
AZURE_OPENAI_ENDPOINT=https://<your-aoai>.openai.azure.com/
AZURE_OPENAI_API_KEY=<key>
AZURE_OPENAI_COMPUTER_USE_DEPLOYMENT=<deployment-name>
# Optional. Defaults to a current preview if unset.
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

What you'll see:

```
==> Booting sandbox (run=a1b2c3d4)...
    sandbox: sb-xxxxxxxx
==> Uploading desktop image from .../desktop-image...
==> Installing desktop (this takes 2-4 minutes the first time)...
desktop ready
==> Exposing ports...
    control : https://sb-xxxxxxxx-7000.<region>.azurecontainerapps.io
    noVNC   : https://sb-xxxxxxxx-6080.<region>.azurecontainerapps.io
==> Locking egress: default = Deny (no allow rules)...

========================================================================
  Watch the agent work in your browser:
    https://sb-xxxxxxxx-6080.<region>.azurecontainerapps.io/vnc.html?autoconnect=1&resize=remote
========================================================================

==> Sending initial prompt to model...
    turn  1: action=screenshot
    turn  2: action=click
    turn  3: action=type
    turn  4: action=keypress
    ...
==> Agent finished.
==> Verifying /tmp/submission.json...
    trip:   'Q4 customer visit - Seattle'
    items:  4
      - Airfare            $  642.18  SEA <-> JFK round-trip
      - Hotel              $  489.00  Westin Seattle 2 nights
      - Meals              $  127.55  Team dinner Tuesday
      - Ground transport   $   84.40  Airport taxi both ways
    total:  $1343.13
    [ok] form submission recorded
==> Deleting sandbox sb-xxxxxxxx...
```

Paste the noVNC URL into Chrome to watch the agent move the cursor, click
into fields, type values, add line items, and submit.

## Files

| File | What it does |
|---|---|
| [`computer_use.py`](python/computer_use.py) | End-to-end: boot sandbox, install desktop, expose ports, run agent loop, verify, delete. |
| [`aca_computer.py`](python/aca_computer.py) | `ACAComputer` adapter — translates each OpenAI `computer_call.action` into an HTTP call against the in-sandbox control server. |
| `requirements.txt` | Pulls `openai`, `requests`, and the shared `azure-containerapps-sandbox` wheel. |

The desktop itself (`Xvfb` + Chromium + `xdotool` + noVNC + the FastAPI
control server + the demo form) lives one level up, in
[`../desktop-image/`](../desktop-image/), so it can be shared with future
vendors.

## Adapting the demo

- **Drive a real website.** Change `TASK_PROMPT` in `computer_use.py` and
  swap the Chromium `--app=http://localhost:8080/` flag in `setup.sh` to
  the target URL. Then add the target's hostname to the egress allowlist:
  ```python
  sandbox.add_egress_host_rule("*.example.com", action="Allow")
  ```
- **Change the screen size.** Update both `DISPLAY_W`/`DISPLAY_H` in
  `computer_use.py` *and* the `Xvfb :99 -screen 0 1280x800x24` line in
  `setup.sh` to match.
- **Persist the desktop.** After `setup.sh` finishes once, `begin_commit`
  the sandbox to a disk (see [guide 03](../../../guides/03-disks)) and
  reboot from `disk_id=` next time. Drops setup from ~3 min to ~10 sec.

## Troubleshooting

- **`control server at https://... not ready after 90s`** — the public
  port is taking longer than expected to wire up. Bump the
  `wait_until_ready(timeout=...)` call in `computer_use.py`, or check
  the sandbox: `sandbox.exec("tail -n 50 /var/log/desktop/control.log")`.
- **Agent keeps clicking the wrong spot** — the dimensions we report
  in the tool definition (`display_width`/`display_height`) must match
  what Xvfb is actually serving. If you change one, change both.
- **`no submission found`** — the agent gave up before clicking Submit.
  Re-run with the noVNC tab open to see where it got stuck. Increase
  `MAX_AGENT_TURNS` if it ran out, or simplify the prompt if it looped.

## Reference

- Azure OpenAI computer use — <https://learn.microsoft.com/azure/ai-services/openai/how-to/computer-use>
- OpenAI Responses API computer-use tool — <https://platform.openai.com/docs/guides/tools-computer-use>
