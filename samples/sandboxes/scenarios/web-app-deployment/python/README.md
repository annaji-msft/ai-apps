# Web app deployment (Python)

```bash
pip install -r requirements.txt
python deploy.py
```

The first run is slower because the `node-22` disk image has to be
fetched. Subsequent runs reuse it from the sandbox group.
