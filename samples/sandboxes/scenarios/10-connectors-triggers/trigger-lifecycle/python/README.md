# Trigger lifecycle (Python)

CRUD walk-through of the connector-gateway trigger config API. Uses
the working `azure.containerapps.sandbox.SandboxClient` data-plane
client plus `az rest` for the trigger ARM surface (until the trigger
SDK ships).

## What it does

1. Discovers available trigger operations on `office365`.
2. Creates a fresh sandbox + a tiny stdlib webhook listener on `:5000`.
3. Adds port 5000 with the gateway MI in `entraId.objectIds` (the
   gateway's calls authenticate as its own MI; your `ACA_USER_EMAIL`
   is also added so you can hit the URL from your browser).
4. PUTs a trigger config with `OnNewEmailV3` (InvokePort target).
5. Lists / disables / enables the trigger config.
6. Cleans up in the right order: **trigger config first**, then port,
   then sandbox. (Leaving a trigger pointing at a deleted sandbox is
   how you end up with stale subscriptions and confused logs.)

This walk-through **does not** wait for a real email to fire the trigger —
that's what the scenario in
`samples/sandboxes/scenarios/10-connectors-triggers/email-to-sandbox` is for. The point
here is the lifecycle.

## Prerequisites

- Both prerequisites applied:
  - `python samples/sandboxes/setup/python/setup.py`
  - `python samples/sandboxes/scenarios/10-connectors-triggers/setup/python/setup.py`
- `az login` complete.

## Run

```bash
pip install -r requirements.txt
python trigger.py
```

## Files

| File | Purpose |
|---|---|
| `trigger.py` | the lifecycle demo |
| `requirements.txt` | inherits the sandboxes baseline |
