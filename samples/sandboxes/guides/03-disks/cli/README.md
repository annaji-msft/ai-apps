# 03 - Disks (CLI)

```bash
./run.sh
```

> Takes ~10-20 min total — two disk builds back-to-back.

## What this shows

| Command | What it does |
|---|---|
| `aca sandboxgroup disk list-public` | List public disk images (valid `--disk` values) |
| `aca sandboxgroup disk create --image <img> --name <n>` | Build a custom disk from a container image |
| `aca sandboxgroup disk list` / `get --id <id>` | Inventory + lookup of your private disks |
| `aca sandbox create --disk-id <id>` | Boot a sandbox from a custom disk (`--disk` is public only) |
| `aca sandbox commit --id <sid> --name <n>` | Freeze a running sandbox into a new disk image |
| `aca sandboxgroup disk delete --id <id>` | Remove a disk image |
