# SDK deep dive

Capabilities of the `azure-containerapps-sandbox` Python SDK that aren't covered by the functional guides ([00 – 13](../)). This is reference material — each section is independent and self‑contained, so jump to whichever one you need.

> Verified against `azure-containerapps-sandbox 0.1.0b1`. Every code snippet was executed before being pasted; output blocks show what was actually observed.

## Contents

- [Clients](#clients) — what the three clients do and how to obtain a `SandboxClient`
- [Async](#async) — the `aio` namespace for concurrent workloads
- [Logging](#logging) — pass your own `Logger`, see HTTP on the wire
- [Exceptions](#exceptions) — what gets raised and how to handle it
- [Helpers](#helpers) — `wait_for_running` vs `ensure_running`, region helpers, constants
- [Pollers](#pollers) — the long-running operation surface (sync vs `begin_*`, polling kwargs)

---

## Clients

The SDK exposes **three** top-level clients. Reach for the right one and the rest follows.

| Client | Scope | Use for |
|---|---|---|
| `SandboxGroupManagementClient` | Control plane (ARM) | Create/delete sandbox **groups**, patch identity on a group, list groups in a subscription/RG. |
| `SandboxGroupClient` | Data plane (one group) | Everything inside a group: sandboxes, disks, snapshots, volumes, secrets, public disk images. |
| `SandboxClient` | Data plane (one sandbox) | Exec, files, lifecycle (stop/resume), snapshot/commit, egress, ports, stats. |

### Why customers care

Reaching for the wrong client is the #1 cause of "method not found". `SandboxGroupClient.list_sandboxes()` returns lightweight `Sandbox` dataclasses — they have `.id` and `.state`, but they are **not** `SandboxClient`s. To do anything to an existing sandbox you need an actual `SandboxClient`. Knowing how to obtain one unblocks every "I have a sandbox ID from yesterday — now what?" workflow.

### Construct each client

```python
from azure.identity import DefaultAzureCredential
from azure.containerapps.sandbox import (
    SandboxGroupManagementClient,
    SandboxGroupClient,
)

credential = DefaultAzureCredential()

# Control plane — manages sandbox groups
mgmt = SandboxGroupManagementClient(
    credential=credential,
    subscription_id="<SUB_ID>",
    resource_group="<RG>",
)

# Data plane for one group — everything inside the group
group = SandboxGroupClient(
    credential=credential,
    subscription_id="<SUB_ID>",
    resource_group="<RG>",
    sandbox_group="<GROUP_NAME>",
    region="westus2",
)
```

### Get a `SandboxClient` two ways

**1. From `begin_create_sandbox(...).result()`** — you get back a fully wired `SandboxClient` for the new sandbox.

```python
sb = group.begin_create_sandbox(disk="ubuntu", labels={"name": "dev"}).result()
print(sb.sandbox_id)
out = sb.exec("echo hello")
print(out.stdout)
```

**2. From `group.get_sandbox_client(id)`** — wrap an existing sandbox without re-creating it.

```python
sb = group.get_sandbox_client("00000000-0000-0000-0000-000000000000")
out = sb.exec("uname -a")
```

> `get_sandbox_client` is a local wrap — it doesn't round-trip the service. Call `sb.get()` afterward if you need a fresh `Sandbox` snapshot.

### `Sandbox` dataclass vs `SandboxClient`

```python
# list_sandboxes returns Sandbox dataclasses (lightweight, read-only views).
for s in group.list_sandboxes():
    print(s.id, s.state)              # ← dataclass fields

# Turn one into a SandboxClient when you need to act on it.
sb = group.get_sandbox_client(s.id)   # ← now has .exec/.stop/.resume/etc.
```

### What's on `SandboxClient` (grouped tour)

| Group | Methods |
|---|---|
| Exec & filesystem | `exec`, `read_file`, `write_file`, `delete_file`, `list_files`, `mkdir`, `stat_file` |
| Lifecycle | `stop` / `begin_stop`, `resume` / `begin_resume`, `wait_for_running`, `ensure_running`, `get` |
| Snapshot & commit | `create_snapshot` / `begin_create_snapshot`, `commit` / `begin_commit` |
| Delete | `delete` / `begin_delete` |
| Egress | `set_egress_default`, `set_egress_policy`, `get_egress_policy`, `get_egress_decisions`, `add_egress_host_rule`, `add_egress_rewrite_rule`, `add_egress_transform_rule` |
| Ports | `add_port`, `remove_port`, `update_ports` |
| Volumes | `add_volume_mount` |
| Lifecycle policy | `set_lifecycle_policy` |
| Stats | `get_stats` → `SandboxStats` |

[↑ Back to top](#contents)

---

## Async

Every operation has an async counterpart in `azure.containerapps.sandbox.aio`. Same names, same shapes — but `async`/`await`.

### Why customers care

If you're building a web app, an agent runtime, or any service that drives many sandboxes per request, sync calls block the event loop. The `aio` surface lets a single process drive hundreds of sandboxes concurrently with proper cancellation and timeouts.

### Async clients

```python
import asyncio
from azure.identity.aio import DefaultAzureCredential
from azure.containerapps.sandbox.aio import SandboxGroupClient

async def main():
    async with DefaultAzureCredential() as cred, SandboxGroupClient(
        credential=cred,
        subscription_id="<SUB_ID>",
        resource_group="<RG>",
        sandbox_group="<GROUP_NAME>",
        region="westus2",
    ) as group:
        sandboxes = [s async for s in group.list_sandboxes()]
        print(len(sandboxes))

asyncio.run(main())
```

The `aio` package exports the same three clients: `SandboxClient`, `SandboxGroupClient`, `SandboxGroupManagementClient`.

### Fan-out with `asyncio.gather`

```python
async def boot_n(group, n: int):
    pollers = [
        await group.begin_create_sandbox(disk="ubuntu", labels={"i": str(i)})
        for i in range(n)
    ]
    return await asyncio.gather(*(p.result() for p in pollers))
```

[↑ Back to top](#contents)

---

## Logging

The SDK uses standard Python `logging` and the Azure-core HTTP logging policy. You can plug in your own logger and turn on wire-level traces per call.

### Why customers care

When a call hangs or returns the wrong thing, the first question is *"what was actually sent?"* Built-in HTTP logging answers that without attaching a debugger. Enabling it **per call** keeps production output quiet while letting you crank up detail on a single problem request.

### Set up a logger

```python
import logging
import sys

logging.basicConfig(stream=sys.stdout, level=logging.INFO)
# Azure SDK loggers live under this namespace.
azure_log = logging.getLogger("azure")
azure_log.setLevel(logging.DEBUG)
```

The SDK picks up the `azure` logger hierarchy automatically. No special parameter on the client is required to *use* logging — only to control verbosity.

### Enable HTTP logging on a single call

```python
sb = group.begin_create_sandbox(
    disk="ubuntu",
    logging_enable=True,   # ← per-call HTTP request/response logging
).result()
```

`logging_enable=True` is the standard Azure-core kwarg and works on every SDK method. With your logger at `DEBUG`, you'll see request method, URL, headers, status code, and response headers on stdout.

### Redaction

Azure-core's HTTP logging redacts sensitive headers (`Authorization`, `x-ms-*-key`, etc.) automatically. Body content is **not** logged by default. If you need bodies, set `logging_body=True` on the call — but only in dev: bodies may contain secrets you set with `upsert_secret`.

[↑ Back to top](#contents)

---

## Exceptions

The SDK raises standard `azure.core.exceptions.*` types — they carry the HTTP status and an Azure error payload.

### Why customers care

Robust error handling is what separates a demo from production code. Catching the right exception type lets you handle missing resources, retry transient failures, and surface real errors with full context — instead of swallowing everything with bare `except Exception`.

### The types you'll see

| Exception | When |
|---|---|
| `ResourceNotFoundError` | 404 on a GET (`get_sandbox`, `get_disk_image`, etc.). |
| `HttpResponseError` | Any other non-success status (400, 403, 409, 429, 5xx). Inspect `.status_code` and `.error.code`. |
| `azure.core.exceptions.ClientAuthenticationError` | Credential/token issues — bubble up from the credential. |

### Patterns

```python
from azure.core.exceptions import HttpResponseError, ResourceNotFoundError

# 1) Treat 404 as "doesn't exist" — common during idempotent cleanup.
try:
    group.delete_sandbox(sb_id)
except ResourceNotFoundError:
    pass  # already gone

# 2) Inspect status + error code for everything else.
try:
    group.begin_create_sandbox(disk="ubuntu").result()
except HttpResponseError as e:
    if e.status_code == 429:
        # rate limited — back off
        ...
    elif e.status_code == 409 and e.error and e.error.code == "ConflictingOperation":
        # a previous op on this resource hasn't settled — wait + retry
        ...
    else:
        raise
```

For 429 and 5xx, the SDK retries internally with the Azure-core retry policy; what reaches your code is the *final* failure. If you want different behavior, pass `retry_policy=` when constructing the client.

[↑ Back to top](#contents)

---

## Helpers

Small surface, big quality-of-life. The SDK ships a few helpers and constants that customers tend to reinvent badly.

### Why customers care

`ensure_running` collapses a 10‑line state machine around auto-suspend into one call. Region helpers stop multi-region apps from hardcoding hostnames. The `DATA_PLANE_*` constants and `ApiVersion` enum keep transport details out of your application code.

### `wait_for_running` vs `ensure_running`

Both live on `SandboxClient`. They look similar; they're for different jobs.

```python
# wait_for_running — POLL until Running; returns a refreshed Sandbox dataclass.
# Use after a manual `stop` or when you specifically need the polled snapshot.
state = sb.wait_for_running(timeout=180, poll_interval=3)
print(state.state)   # "Running"

# ensure_running — no return. Idempotent. Transparently handles
# Suspended → Running. Pre-call guard for any operation that needs a live sandbox.
sb.ensure_running(timeout=300)
sb.exec("echo back")
```

| | `wait_for_running` | `ensure_running` |
|---|---|---|
| Returns | refreshed `Sandbox` | nothing |
| Triggers a resume? | No (just polls) | Yes, if Suspended |
| Use when | you want the polled state | you just want the sandbox usable |

### Refresh state explicitly

```python
sb.get()                # GET on the resource; updates internal state cache
```

### Region helpers and constants

```python
from azure.containerapps.sandbox import (
    endpoint_for_region,
    region_from_endpoint,
    DATA_PLANE_BASE,
    DATA_PLANE_SCOPE,
    DATA_PLANE_API_VERSION,
    ApiVersion,
)

endpoint_for_region("westus2")              # → data plane URL for that region
region_from_endpoint(endpoint_url)          # → "westus2"
DATA_PLANE_SCOPE                            # OAuth scope for the data plane
ApiVersion.V2026_02_01_PREVIEW              # enum for pinning API version
```

Use these in tests and multi-region apps instead of hardcoding hostnames.

[↑ Back to top](#contents)

---

## Pollers

Long-running operations (LROs) return an `LROPoller`. There's a sync and an async form for most ops, plus knobs that let you tune timeouts and parallelize.

### Why customers care

If you assume these behave like classic Azure ARM LROs you'll write broken code. Knowing the actual surface lets you tune intervals, set realistic timeouts, build non-blocking UIs, and parallelize batch ops — kick off 20 deletes in milliseconds, then await them as a group.

### Sync vs `begin_*` pairs

Most operations have BOTH a sync form (blocks internally) AND a `begin_*` form (returns a poller). Same arguments, different control flow.

| Sync (blocks)               | Async (`begin_*` returns `LROPoller`) |
|---|---|
| `group.delete_sandbox(id)`  | `group.begin_delete_sandbox(id)` |
| `group.create_disk_image(…)`| `group.begin_create_disk_image(…)` |
| `group.delete_disk_image(id)`| `group.begin_delete_disk_image(id)` |
| `group.delete_snapshot(id)` | `group.begin_delete_snapshot(id)` |
| `group.delete_volume(id)`   | `group.begin_delete_volume(id)` |
| `sb.commit(…)`              | `sb.begin_commit(…)` |
| `sb.create_snapshot(…)`     | `sb.begin_create_snapshot(…)` |
| `sb.stop()` / `sb.resume()` | `sb.begin_stop()` / `sb.begin_resume()` |
| `sb.delete()`               | `sb.begin_delete()` |

Pick sync for scripts where you want the result inline. Pick `begin_*` whenever you want to:

- Run multiple LROs concurrently
- Do other work while one is running
- Poll status from a UI / progress bar
- Set a non-default timeout

### What the poller exposes

```python
poller = group.begin_create_sandbox(disk="ubuntu")

poller.status()        # "InProgress" | "Succeeded" | "Failed"
poller.done()          # bool
poller.wait(timeout=60)  # wait up to N seconds, then return regardless
sandbox_client = poller.result()  # blocks for completion, returns the result
```

> The SDK uses **custom polling algorithms** (`ResourceStatePoller`, `DeletionPoller`, `ResourceExistsPoller`) under the hood. They poll the resource's `state` field — not the standard `Azure-AsyncOperation` / `Location` headers. There is **no `.cancel()`** on the poller: once an LRO is started server-side, you wait for terminal state.

### Tune timeout and interval

Every `begin_*` method accepts two extra kwargs:

```python
poller = group.begin_create_sandbox(
    disk="ubuntu",
    polling_timeout=600,    # default 300 — fail after this many seconds
    polling_interval=5,     # default 3   — sleep this many seconds between polls
)
sb = poller.result()
```

Lower `polling_interval` for fast tests (more polls, faster detection of state changes). Higher for cost-sensitive long jobs.

### Parallel fan-out

```python
ids = [s.id for s in group.list_sandboxes()]
pollers = [group.begin_delete_sandbox(i) for i in ids]
[p.result() for p in pollers]   # all deletes run concurrently server-side
```

Same pattern works for parallel creates, snapshots, image builds — anywhere you've got a `begin_*` method and a batch of inputs.

[↑ Back to top](#contents)
