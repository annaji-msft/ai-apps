"""Web app in a sandbox — Entra ID protected port (Python SDK).

Same flow as ``webapp_anonymous.py`` except the public port is gated by
Entra ID: only the email in ``ACA_USER_EMAIL`` (captured at setup time)
can sign in to access it.

Verification:
  * In-sandbox curl returns 200 + JSON shape (no proxy in the path).
  * Host-side anonymous curl returns a non-2xx — proves the gate works.
  * Programmatic curl with a bearer token is intentionally not attempted
    here (the token audience for the port proxy is platform-defined and
    isn't documented in the SDK reference). Open the URL in a browser and
    sign in as ``ACA_USER_EMAIL`` to reach the app interactively.

Reads configuration from ``samples/.env`` (written by
``samples/sandboxes/setup/python/setup.py`` or ``setup/cli/setup.sh``).
"""

from __future__ import annotations

import json
import os
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

from azure.identity import DefaultAzureCredential
from azure.containerapps.sandbox import (
    SandboxGroupClient,
    endpoint_for_region,
)

SCENARIO_DIR = Path(__file__).resolve().parent.parent
APP_DIR = SCENARIO_DIR / "app"
PORT = 8080


def _load_env() -> None:
    for parent in Path(__file__).resolve().parents:
        env = parent / ".env"
        if env.is_file():
            for line in env.read_text().splitlines():
                if line and not line.startswith("#") and "=" in line:
                    k, v = line.split("=", 1)
                    os.environ.setdefault(k.strip(), v.strip())
            break
    if not os.environ.get("ACA_SANDBOXGROUP_REGION"):
        sys.exit(
            "error: samples/.env is missing required keys. Run:\n"
            "       python samples/sandboxes/setup/python/setup.py"
        )


def _poll_in_sandbox(sandbox, url: str, timeout_s: int = 30) -> None:
    deadline = time.monotonic() + timeout_s
    last = ""
    while time.monotonic() < deadline:
        result = sandbox.exec(
            f"curl -fsS -o /dev/null -w '%{{http_code}}' {url} || true"
        )
        last = (result.stdout or "").strip()
        if last == "200":
            return
        time.sleep(1)
    log = sandbox.exec("cat /tmp/node.log 2>/dev/null || true")
    raise RuntimeError(
        f"server not ready after {timeout_s}s (last http_code={last!r}); "
        f"node.log:\n{(log.stdout or '').strip()}"
    )


def _poll_in_sandbox_json(sandbox, url: str) -> dict:
    result = sandbox.exec(f"curl -fsS {url}")
    if result.exit_code != 0:
        raise RuntimeError(f"in-sandbox curl failed for {url}: {result.stderr}")
    return json.loads(result.stdout)


def _poll_public_unauthenticated(url: str, timeout_s: int = 60) -> int:
    """Hit `url` without auth until proxy answers; return the (non-200) status."""
    deadline = time.monotonic() + timeout_s
    last_status = 0
    while time.monotonic() < deadline:
        req = urllib.request.Request(url, method="GET")
        try:
            with urllib.request.urlopen(req, timeout=10) as resp:
                last_status = resp.status
        except urllib.error.HTTPError as e:
            last_status = e.code  # the proxy answered with a status — what we want
            if last_status in (401, 403):
                return last_status
            if last_status == 302:  # redirect to login is also fine
                return last_status
        except urllib.error.URLError:
            pass
        # 200 means the proxy isn't enforcing auth yet, keep polling
        if last_status and last_status != 200:
            return last_status
        time.sleep(2)
    raise RuntimeError(
        f"proxy did not return a recognizable non-2xx after {timeout_s}s "
        f"(last status: {last_status}); is the Entra gate up?"
    )


def main() -> None:
    _load_env()
    disk = os.environ.get("ACA_WEBAPP_DISK", "node-22")
    email = os.environ.get("ACA_USER_EMAIL", "").strip()
    if not email:
        sys.exit(
            "error: ACA_USER_EMAIL is empty in samples/.env. This scenario "
            "gates the public port to a specific Entra ID user. Re-run "
            "setup as a human user, or set ACA_USER_EMAIL manually in "
            "samples/.env to a member of your tenant."
        )

    credential = DefaultAzureCredential()
    client = SandboxGroupClient(
        endpoint_for_region(os.environ["ACA_SANDBOXGROUP_REGION"]),
        credential,
        subscription_id=os.environ["AZURE_SUBSCRIPTION_ID"],
        resource_group=os.environ["ACA_RESOURCE_GROUP"],
        sandbox_group=os.environ["ACA_SANDBOX_GROUP"],
    )

    sandbox = None
    port_added = False
    try:
        print(f"==> Creating sandbox (disk={disk})...")
        sandbox = client.begin_create_sandbox(disk=disk).result()
        print(f"    sandbox: {sandbox.sandbox_id}")

        print(f"==> Uploading app from {APP_DIR.relative_to(SCENARIO_DIR.parent)}...")
        sandbox.exec("mkdir -p /app")
        sandbox.write_file("/app/server.js", (APP_DIR / "server.js").read_text())
        sandbox.write_file("/app/package.json", (APP_DIR / "package.json").read_text())

        print(f"==> Starting Node server on :{PORT}...")
        sandbox.exec(
            f"cd /app && nohup node server.js > /tmp/node.log 2>&1 &"
        )

        print("==> Polling in-sandbox readiness on /healthz...")
        _poll_in_sandbox(sandbox, f"http://localhost:{PORT}/healthz")
        print("    server is ready")

        print("==> In-sandbox JSON shape checks...")
        hello = _poll_in_sandbox_json(sandbox, f"http://localhost:{PORT}/api/hello")
        assert hello.get("message") == "Hello from sandbox", hello
        health = _poll_in_sandbox_json(sandbox, f"http://localhost:{PORT}/healthz")
        assert health.get("status") == "ok", health
        info = _poll_in_sandbox_json(sandbox, f"http://localhost:{PORT}/api/info")
        assert "node" in info and "platform" in info, info
        print(f"    GET /api/hello -> {hello}")
        print(f"    GET /healthz   -> {health}")
        print(f"    GET /api/info  -> {info}")
        # And the HTML landing page.
        root = sandbox.exec(f"curl -fsS -o /dev/null -w '%{{http_code}}' http://localhost:{PORT}/")
        assert (root.stdout or "").strip() == "200", root.stdout
        print(f"    GET /           -> http 200 (HTML landing page)")

        print(f"==> add_port({PORT}, email={email!r})")
        port = sandbox.add_port(PORT, email=email)
        port_added = True
        url = getattr(port, "url", None)
        if not url:
            raise RuntimeError("add_port did not return a URL")
        print(f"    public URL: {url}")

        print("==> Verifying the Entra ID gate (host-side, NO auth)...")
        status = _poll_public_unauthenticated(url)
        assert status != 200, (
            f"expected the Entra gate to reject anonymous access but got "
            f"http {status} — is `email=` actually being honored?"
        )
        print(f"    anonymous GET -> http {status} (gate is working)")

        print()
        print("==> Done. To reach the app interactively:")
        print(f"    open {url}")
        print(f"    and sign in as {email}")
    finally:
        if sandbox is not None and port_added:
            try:
                print(f"==> remove_port({PORT})")
                sandbox.remove_port(PORT)
            except Exception as e:
                print(f"    warning: remove_port failed: {e}")
        if sandbox is not None:
            try:
                print(f"==> Deleting sandbox {sandbox.sandbox_id}...")
                sandbox.delete()
            except Exception as e:
                print(f"    warning: delete failed: {e}")
        client.close()
        credential.close()


if __name__ == "__main__":
    main()
