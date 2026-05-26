# Web apps — `aca` CLI

Two scripts, same shared app in [`../app/`](../app/):

| Script | What it shows |
|--------|---------------|
| [`run_anonymous.sh`](run_anonymous.sh) | `aca sandbox port add --port 8080 --anonymous` — open to the internet |
| [`run_protected.sh`](run_protected.sh) | `aca sandbox port add --port 8080 --email $ACA_USER_EMAIL` — gated by Entra ID |

## Run

```bash
bash run_anonymous.sh
bash run_protected.sh
```

Both read configuration from `samples/.env`. Override the disk image with
`ACA_WEBAPP_DISK=...` (default: `node-22`).

`run_protected.sh` needs `ACA_USER_EMAIL` in `samples/.env`. Setup
captures it automatically for human users (from `az account show --query
user.name`). Service-principal callers need to set it manually.
