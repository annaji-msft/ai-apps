# 07 - Files (CLI)

```bash
./run.sh
```

## What this shows

| Command | What it does |
|---|---|
| `aca sandbox fs write --path P --file LOCAL` | Upload a local file |
| `aca sandbox fs cat --path P` | Print file contents |
| `aca sandbox fs stat --path P` | File metadata |
| `aca sandbox fs mkdir --path P` | Create a directory |
| `aca sandbox fs ls --path P` | List directory contents |
| `aca sandbox fs rm --path P [--recursive]` | Delete file or directory |

> Note: `aca sandbox fs write` takes a **local** file path. The script
> stages one in `$TEMP` first.
