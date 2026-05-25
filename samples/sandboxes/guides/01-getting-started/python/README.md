# 01 - Getting started (Python)

```bash
# One-time, from samples/sandboxes/setup/:  python setup.py
pip install -r requirements.txt
python getting_started.py
```

## What this shows

| API | What it does |
|---|---|
| `SandboxGroupClient` | Data-plane client, region-scoped |
| `begin_create_sandbox(disk="ubuntu")` | Async create from a public disk image |
| `sandbox.exec(cmd)` | Run a shell command, get stdout/stderr/exit code |
| `sandbox.delete()` | Tear down (called in `finally`) |
