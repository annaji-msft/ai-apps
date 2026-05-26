# 01-webapps — Web apps in sandboxes

Run a real web application inside a sandbox: upload a multi-file Node.js
app from your laptop, start it in the background, expose port 8080 to the
internet, and verify the response from both inside the sandbox **and** from
the host machine. Two variants ship side-by-side — pick the access-control
mode you want.

Composes guides 01 (sandboxes) + 06 (ports) + 07 (files).

## What you get

- A small Node.js HTTP server (in [`app/`](app/)) with three endpoints:
  - `GET /` → `{ "message": "Hello from sandbox", "hostname", "uptime" }`
  - `GET /healthz` → `{ "status": "ok" }`
  - `GET /api/info` → `{ "node": "v22.x", "platform": "linux" }`
- A Python SDK and an `aca` CLI driver, each in two variants.
- Bounded readiness polling (no fragile `sleep N`) and JSON-shape
  assertions on every endpoint.
- A try/finally cleanup that removes the port before deleting the sandbox.

## Variants

| Variant | What `add_port` does | What you verify from your host |
|---|---|---|
| **Anonymous** | `add_port(8080, anonymous=True)` | Anyone with the URL gets `200` + JSON. Polled from the host machine. |
| **Protected** | `add_port(8080, email="$ACA_USER_EMAIL")` | Anonymous requests get a non-2xx (`401` / `403` / `302`) — the Entra ID gate is in front. Open the URL in a browser and sign in as that email to reach the app interactively. |

Both variants run the **same** Node app, do the same in-sandbox readiness
poll, and clean up the same way. Only the port-add call and the host-side
verification differ.

## Run it

### Python SDK

```bash
cd python
pip install -r requirements.txt

python webapp_anonymous.py     # variant A
python webapp_protected.py     # variant B
```

### `aca` CLI

```bash
cd cli
bash run_anonymous.sh          # variant A
bash run_protected.sh          # variant B
```

Both flows read configuration from `samples/.env`. Override the disk image
with `ACA_WEBAPP_DISK=...` (default: `node-22`).

The protected variant needs `ACA_USER_EMAIL` in `samples/.env`. Setup
captures it automatically for human users (Python: from the
`upn`/`preferred_username` claim in the management token; CLI:
`az account show --query user.name`). Service-principal callers must set
it manually — the protected script exits early with a clear error
otherwise.

## Production tips

- **Pick your auth mode deliberately.** Anonymous ports are open to the
  internet — don't lean on URL obscurity, remove ports promptly, and never
  serve secrets from a demo endpoint. Email-gated Entra ID is the right
  default for anything customer-facing. For programmatic clients, mint a
  token for the right audience and send it as `Authorization: Bearer …`.
- **Bake the disk.** Pre-install your dependencies into a custom disk
  image ([guide 03](../../guides/03-disks/README.md)) so startup is "boot",
  not "boot + npm install".
- **One sandbox per tenant/user.** Tag with `labels=`
  ([guide 11](../../guides/11-labels/README.md)) so you can find the right
  one with `list_sandboxes(labels=...)`.
- **Snapshots for warm starts.** Snapshot post-build
  ([guide 02](../../guides/02-snapshots/README.md)) and resume into it on
  each request — much faster than a cold boot.
- **Auto-suspend / auto-delete.** Use `AutoSuspendPolicy`
  ([guide 05](../../guides/05-lifecycle/README.md)) so idle sandboxes don't
  burn quota.
- **Egress lockdown.** If the webapp shouldn't reach the internet,
  `set_egress_default("Deny")` and allow only the hosts it needs
  ([guide 08](../../guides/08-egress/README.md)).

## Layout

```
01-webapps/
├── README.md              ← this file
├── app/                   ← shared Node app (used by both python and cli)
│   ├── server.js
│   └── package.json
├── python/
│   ├── README.md
│   ├── requirements.txt
│   ├── webapp_anonymous.py
│   └── webapp_protected.py
└── cli/
    ├── README.md
    ├── run_anonymous.sh
    └── run_protected.sh
```
