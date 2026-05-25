# Web app deployment (CLI)

```bash
./run.sh
./run.ps1
```

The first run is slower because the `node-22` disk image has to be
fetched. Subsequent runs reuse it from the sandbox group.
