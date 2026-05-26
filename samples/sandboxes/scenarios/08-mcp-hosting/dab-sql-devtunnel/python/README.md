# dab-sql-devtunnel — Python SDK driver

```bash
pip install -r requirements.txt
python run.py
```

Configuration comes from `samples/.env` (written by
`samples/sandboxes/setup/python/setup.py`).

**One-time interactive step:** the script will pause and print a Dev
Tunnels device-code login URL + code. Open it in your browser, sign in
with any Microsoft / GitHub account, then return to the terminal — the
token is cached inside the sandbox for the rest of the run.

See the [pattern README](../README.md) for full architecture and
verification details.
