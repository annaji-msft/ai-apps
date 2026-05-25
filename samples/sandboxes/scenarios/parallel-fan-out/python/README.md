# Parallel fan-out (Python)

```bash
pip install -r requirements.txt
python fan_out.py
```

Defaults to `N=4` workers. Override:

```bash
NUM_WORKERS=8 python fan_out.py
```

Each worker computes `item ** 2` inside its sandbox and the orchestrator
prints the collected `{input: output}` map plus the wall-clock vs
sequential comparison.
