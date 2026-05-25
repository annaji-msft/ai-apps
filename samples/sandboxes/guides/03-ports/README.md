# 03 - Ports

Expose a port on a sandbox and hit it from outside. Demonstrates
`add_port(anonymous=True)` and `remove_port`.

- [`python/`](python/) - Python SDK
- [`cli/`](cli/) - `aca` CLI (bash + PowerShell)

## What it does

1. Start a sandbox
2. Launch a 1-line HTTP server inside the sandbox on `:8080`
3. Call `add_port(8080, anonymous=True)` to get a public URL
4. Curl that URL from your local machine
5. `remove_port(8080)` and tear down
