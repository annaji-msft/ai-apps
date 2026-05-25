# 04 - Snapshots

Capture sandbox state as a snapshot, then boot a new sandbox from it
and verify the data is preserved.

- [`python/`](python/) - Python SDK
- [`cli/`](cli/) - `aca` CLI (bash + PowerShell)

## What it does

1. Start sandbox A
2. Write `/tmp/payload.txt` inside it
3. `create_snapshot()`
4. Boot sandbox B from that snapshot
5. Read `/tmp/payload.txt` in sandbox B - it's there
6. Clean up both sandboxes and the snapshot
