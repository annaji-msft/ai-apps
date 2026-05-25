# Guide 10 — Custom disk images

Build a custom disk image from any container image (public or private)
once, then boot sandboxes from it. Faster than installing packages on
every sandbox.

- [`python/`](python/) — `group.begin_create_disk_image("docker.io/library/alpine:3.19", name="...")`
- [`cli/`](cli/) — `aca sandboxgroup disk create --image alpine:3.19 --name my-alpine`

## What's covered

| API | Python | CLI |
|---|---|---|
| Build from public image | `begin_create_disk_image("alpine:3.19", name="x")` | `disk create --image alpine:3.19 --name x` |
| Build from private (ACR) | `begin_create_disk_image(..., registry_credentials=RegistryCredentials(...))` | `disk create --image acr.azurecr.io/img --username U --token T` |
| Build with managed identity | `begin_create_disk_image(..., managed_identity_resource_id="...")` | `disk create --identity system` (or full resource ID) |
| List | `list_disk_images()` | `disk list` |
| Boot from custom | `begin_create_sandbox(disk_id=image_id)` | `aca sandbox create --disk <name>` |
| Delete | `begin_delete_disk_image(image_id)` | `disk delete --id $ID` |

## Demo flow

1. `begin_create_disk_image("docker.io/library/alpine:3.19", name="alpine-demo-…")`
2. Poll until `status.state == "Ready"` (the LROPoller does this for you)
3. Boot a sandbox using the new disk id
4. `exec("cat /etc/alpine-release")` — proves we booted into Alpine
5. Tear down sandbox + disk image

> **Heads up**: building a disk image can take **5-10 minutes** the first
> time. The script's poller defaults to a 10-minute timeout.

## Why this matters

For LLM agent workloads you'll typically want a custom base: pre-baked
Python venv + model weights + your tool binaries. Build the disk once;
every subsequent sandbox boots in seconds.
