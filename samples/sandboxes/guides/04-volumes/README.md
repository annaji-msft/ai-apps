# 04 - Volumes

Persistent storage that survives sandbox deletion. Two flavors:

- **AzureBlob** — shared across sandboxes; great for producer/consumer
  pipelines or fan-out result aggregation.
- **DataDisk** — block storage; one sandbox at a time, lower latency.

Create a volume on the group, then mount it into one or more sandboxes
with `add_volume_mount` (after create) or by passing `volumes=[...]`
to `begin_create_sandbox`.

- [`python/`](python/) — `group.create_volume(...)` + `sandbox.add_volume_mount(AddVolumeMountRequest(...))`
- [`cli/`](cli/) — `aca sandboxgroup volume create` + `aca sandbox mount`

## What's covered

| API | Python | CLI |
|---|---|---|
| Create AzureBlob volume | `create_volume("name", type="AzureBlob")` | `volume create --name X --type AzureBlob` |
| Create DataDisk volume | `create_volume("name", type="DataDisk", size="1Gi")` | `volume create --name X --type DataDisk --size 1Gi` |
| List | `list_volumes()` | `volume list` |
| Mount on existing sandbox | `sandbox.add_volume_mount(AddVolumeMountRequest(...))` | `aca sandbox mount --volume X --path /mnt/x` |
| Mount at create-time | `begin_create_sandbox(volumes=[SandboxVolume(...)])` | `aca sandbox apply --file ...` |
| Delete | `delete_volume("name")` | `volume delete --name X` |

## Demo flow

1. Create an AzureBlob volume
2. Spin up a **producer** sandbox, mount the volume, write `/mnt/shared/output.json`
3. Spin up a **consumer** sandbox, mount the same volume, `cat` the file
4. Tear down both sandboxes; delete the volume

## Why this matters

Volumes are the standard answer to "how do my sandboxes share state?"
For LLM workloads: cache model weights once, mount everywhere; persist
intermediate tool outputs across an agent's turns; coordinate parallel
workers via blob writes.
