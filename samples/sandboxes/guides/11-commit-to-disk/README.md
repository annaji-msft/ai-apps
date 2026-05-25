# Guide 11 — Commit to disk

`sandbox.commit()` freezes the current sandbox state (installed
packages, config, downloaded data) into a new disk image. Boot future
sandboxes from that disk to skip the warm-up cost.

This is "golden image as a service" — set up once interactively, commit,
then your fleet boots from the prepared image.

- [`python/`](python/) — `sandbox.begin_commit(name="my-disk-v1")`
- [`cli/`](cli/) — `aca sandbox commit --id $ID --name my-disk-v1`

## What's covered

| API | Python | CLI |
|---|---|---|
| Commit current state | `sandbox.begin_commit(name="x")` | `aca sandbox commit --id $ID --name x` |
| Boot from committed disk | `begin_create_sandbox(disk=x)` | `aca sandbox create --disk x` |
| Verify state preserved | (write file → commit → boot → read file) | same |

## Demo flow

1. Boot a sandbox; write `/opt/marker.txt` to simulate "setup work"
2. `sandbox.begin_commit(name="committed-…")` and wait until Ready
3. Boot a **new** sandbox from that disk
4. `read_file("/opt/marker.txt")` — should be present

> Commit is similar to **snapshots** ([guide 04](../04-snapshots)) but
> different. Snapshots are restore points within a sandbox group.
> Committing creates an immutable **disk image** that's reusable like
> any other base image — boot infinitely many sandboxes from it.

## Why this matters

Two common workflows:

- **Golden agent image**: dev installs Python deps + model weights once,
  commits, and the production agent fleet boots from that image.
- **Checkpoint**: take a commit before a risky operation; if it goes bad,
  delete the sandbox and spin up a fresh one from the commit.
