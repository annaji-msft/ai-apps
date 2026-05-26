# Web apps — Python SDK

Two scripts, same shared app in [`../app/`](../app/):

| Script | What it shows |
|--------|---------------|
| [`webapp_anonymous.py`](webapp_anonymous.py) | `add_port(8080, anonymous=True)` — open to the internet; host-side curl returns 200 + JSON |
| [`webapp_protected.py`](webapp_protected.py) | `add_port(8080, email=ACA_USER_EMAIL)` — gated by Entra ID; host-side anonymous curl returns non-2xx (proves the gate); interactive access in a browser |

## Run

```bash
pip install -r requirements.txt

python webapp_anonymous.py
python webapp_protected.py
```

Both read configuration from `samples/.env`. Override the disk image with
`ACA_WEBAPP_DISK=...` (default: `node-22`).

`webapp_protected.py` needs `ACA_USER_EMAIL` in `samples/.env`. Setup
captures it automatically for human users (from the JWT
`upn` / `preferred_username` claim). Service-principal callers need to set
it manually.
