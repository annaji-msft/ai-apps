# Scenario — email → sandbox → AI-composed reply (Python)

Lifts `../app/server.py` into a sandbox built on the
[`copilot` disk image](https://learn.microsoft.com/azure/container-apps/sandbox-disk-images),
creates the sandbox with `gatewayConnections=[{ resourceId }]` so the
platform proxy injects the Bearer for outbound calls to the Office 365
connection, locks egress down to the GitHub Copilot CLI hosts only,
wires up `OnNewEmailV3` with `subjectFilter=Feedback`, and waits.

Each incoming feedback email is handed to `copilot -p` inside the
sandbox to compose a warm, personalized acknowledgment; the reply
is sent back through the **same** Office 365 connection via
`SendMailV2`. See [`../README.md`](../README.md) for the GitHub-token
prerequisite.

## Run

```bash
pip install -r requirements.txt
python run.py
```

## What you'll see

```
==> Resolving GitHub token for Copilot CLI...
    using token from `gh auth token`
==> Creating sandbox in 'aca-sandbox-group' (labels.run=ab12cd34) with gatewayConnections=[o365-conn]...
==> Verifying copilot CLI is present...
==> Uploading app/server.py into /app...
==> Starting listener on :5000 (setsid, logs at /tmp/listener.log)...
==> Locking down egress: Deny + GitHub host-Allow only...
==> Egress smoke test: GET <runtime-host>/v2/Mail?folderPath=Inbox&top=1...
    egress ok — runtime URL reachable + platform auth-injection working
==> Verifying Copilot CLI auth (one-shot 'ready' probe)...
    copilot CLI auth ok
==> add port 5000 (entraId.objectIds=[gateway MI])
==> PUT trigger config 'email-to-sandbox-demo'...

========================================================================
Email-to-sandbox trigger is live
========================================================================
  trigger config:  email-to-sandbox-demo (state=Enabled)
  listener URL:    https://sandbox-xxx--5000.proxy.azuredevcompute.io  (healthz only)
  callback URL:    https://sandbox-xxx--5000.proxy.azuredevcompute.io/webhook
  reply goes to:   alice@contoso.com

To fire the trigger:
  1. Send yourself ... an email whose subject contains 'Feedback' ...
  2. Wait ~1 minute — Office 365 trigger delivery is not instant.
  3. Watch alice@contoso.com's inbox for a reply with subject
     'Auto-ack: received your message'.

Listener logs (from another terminal):
  aca sandbox exec -g aca-rg --group aca-sandbox-group \
    --id sandbox-xxx --command 'tail -f /tmp/listener.log'
```

## Cleanup

The script's `finally` block deletes the trigger, the port, and the
sandbox in that order. If you Ctrl-C before the sandbox is created,
the script sweeps any sandbox tagged with this run's UUID.

The scenario baseline (gateway / Office 365 connection / access
policies / sandbox-group MI) is **not** touched — re-run as many
scenarios as you like on the same gateway. Use
`../../setup/python/teardown.py` when you're finally done.
