# Trigger lifecycle

Minimal CRUD walk-through of the connector-gateway trigger surface:
**discover → create → list → disable → enable → delete**, with a
small Python stdlib listener inside the sandbox so the callback URL
is real (the gateway can actually reach it).

This walk-through is **only about the lifecycle**. It doesn't wait for a
real email to fire the trigger — for that, see the scenario at
`../../scenarios/01-email-to-sandbox`.

## Flavors

| Language | Folder | Stack |
|---|---|---|
| Python | [`python/`](python) | `azure.containerapps.sandbox.SandboxClient` + `az rest` |
| CLI    | [`cli/`](cli)       | `aca` + `az rest` |

Both:

1. PUT a sandbox with the `ubuntu` disk and start a `http.server`-based
   POST listener on `:5000`.
2. Add port 5000 with the gateway managed identity in
   `entraId.objectIds` (so the gateway's authenticated request reaches
   the proxy), and your own `ACA_USER_EMAIL` in `entraId.emails` so
   you can also hit the URL from your browser.
3. PUT a trigger config: InvokePort target, `operationName=OnNewEmailV3`,
   `folderPath=Inbox`.
4. List, disable, enable the trigger config.
5. Tear down in the right order: **trigger config → port → sandbox**.
   (Deleting the sandbox first leaves a dangling subscription on the
   connector.)

## Prerequisites

Both baselines applied:

```bash
# Once per workstation:
python ../../../sandboxes/setup/python/setup.py    # or .../cli/setup.sh
python ../../setup/python/setup.py                 # or .../cli/setup.sh
```

## SDK status

Triggers don't yet have a typed Python or aca CLI surface. Both
flavors drive the ARM resource type `Microsoft.Web/connectorGateways`
at api-version `2026-05-01-preview` via `az rest`. When the SDK ships,
those `az rest` calls become one-liners and these samples will be
swapped in a focused PR.
