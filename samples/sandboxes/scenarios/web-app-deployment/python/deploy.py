"""Web app deployment - run a Node.js HTTP server inside a sandbox and
expose it on a public URL.

Composes: write_file (upload app) + exec (start server) + add_port (publish).

Reads configuration from samples/.env (written by samples/sandboxes/setup/setup.py).
"""

from __future__ import annotations

import json
import os
import time
import urllib.request
from pathlib import Path

from azure.identity import DefaultAzureCredential
from azure.containerapps.sandbox import (
    SandboxGroupClient,
    endpoint_for_region,
)

APP_CODE = """\
const http = require('http');
const os = require('os');

http.createServer((req, res) => {
  res.writeHead(200, {'Content-Type': 'application/json'});
  res.end(JSON.stringify({
    message: 'Hello from sandbox!',
    hostname: os.hostname(),
    uptime: process.uptime(),
    path: req.url,
  }, null, 2));
}).listen(8080, '0.0.0.0', () => console.log('Server on :8080'));
"""


def _load_env() -> None:
    for parent in Path(__file__).resolve().parents:
        env = parent / ".env"
        if env.is_file():
            for line in env.read_text().splitlines():
                if line and not line.startswith("#") and "=" in line:
                    k, v = line.split("=", 1)
                    os.environ.setdefault(k.strip(), v.strip())
            return


def main() -> None:
    _load_env()
    credential = DefaultAzureCredential()
    client = SandboxGroupClient(
        endpoint_for_region(os.environ["ACA_SANDBOXGROUP_REGION"]),
        credential,
        subscription_id=os.environ["AZURE_SUBSCRIPTION_ID"],
        resource_group=os.environ["ACA_RESOURCE_GROUP"],
        sandbox_group=os.environ["ACA_SANDBOX_GROUP"],
    )

    sandbox = None
    try:
        print("==> Booting sandbox from 'node-22' disk image...")
        sandbox = client.begin_create_sandbox(disk="node-22").result()
        print(f"    sandbox: {sandbox.sandbox_id}")
        time.sleep(10)

        print("==> Uploading /app/index.js...")
        sandbox.write_file("/app/index.js", APP_CODE)

        print("==> Starting server (nohup node /app/index.js)...")
        sandbox.exec("cd /app && nohup node index.js > /tmp/node.log 2>&1 &")
        time.sleep(3)

        # Sanity-check from inside the sandbox first.
        local = sandbox.exec("curl -s http://localhost:8080 || cat /tmp/node.log")
        print(f"    in-sandbox curl: {(local.stdout or '').strip()[:100]}")

        print("==> Publishing port 8080...")
        port = sandbox.add_port(8080, anonymous=True)
        url = getattr(port, "url", None)
        if not url:
            raise RuntimeError("add_port did not return a URL")
        print(f"    public URL: {url}")

        print("==> Hitting public URL from this machine...")
        time.sleep(8)
        with urllib.request.urlopen(url, timeout=15) as resp:
            body = resp.read().decode()
        # Pretty-print for the demo.
        try:
            payload = json.loads(body)
            print(json.dumps(payload, indent=2))
        except json.JSONDecodeError:
            print(body)

        print("==> Done.")
    finally:
        if sandbox is not None:
            print(f"==> Deleting sandbox {sandbox.sandbox_id}...")
            sandbox.delete()
        client.close()
        credential.close()


if __name__ == "__main__":
    main()
