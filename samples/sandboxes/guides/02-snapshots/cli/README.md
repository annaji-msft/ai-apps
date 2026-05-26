# 02 - Snapshots (CLI)

```bash
./run.sh
```

## What this shows

| Command | What it does |
|---|---|
| `aca sandbox snapshot --id <id> --name <name>` | Capture sandbox state |
| `aca sandbox create --snapshot <name>` | Boot a new sandbox from a snapshot |
| `aca sandboxgroup snapshot delete --selector name=<name>` | Remove the snapshot |
