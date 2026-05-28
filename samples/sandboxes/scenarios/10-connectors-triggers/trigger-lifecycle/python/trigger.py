"""Trigger lifecycle CRUD demo (Python).

End-to-end walk-through of the four primitive trigger operations:

  1. Discover trigger operations on the connected office365 API.
  2. Create a sandbox + a tiny Python webhook listener on :5000.
  3. Add port 5000 with the gateway MI in the entraId.objectIds list
     (so the gateway can actually reach the listener).
  4. PUT a trigger config (InvokePort, points at the sandbox listener).
  5. List, GET, disable, enable, delete the trigger config.
  6. Tear everything down — trigger first, then port, then sandbox.

The trigger is created against the office365 connection set up by
``samples/sandboxes/scenarios/10-connectors-triggers/setup/python/setup.py``. The connection IS connected
to a real mailbox, but this walk-through DOES NOT wait for a real email to
fire it; the goal is to demonstrate the lifecycle ARM surface, not the
end-to-end event flow (the scenario does that).

Reads configuration from ``samples/.env`` (written by both setup scripts:
setup scripts).
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
import time
import uuid
from pathlib import Path

from azure.identity import DefaultAzureCredential
from azure.containerapps.sandbox import (
    SandboxGroupClient,
    endpoint_for_region,
)

API_VERSION = "2026-05-01-preview"
DATAPLANE_API_VERSION = "2026-02-01-preview"
DATAPLANE_RESOURCE = "https://dynamicsessions.io"
PORT = 5000

WEBHOOK_SERVER = r"""
import http.server, json, sys
class H(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        n = int(self.headers.get("Content-Length", "0") or 0)
        body = self.rfile.read(n).decode("utf-8", "replace") if n else ""
        sys.stdout.write(f"WEBHOOK {self.path} body={body[:120]}\n")
        sys.stdout.flush()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(b'{"ok":true}')
    def log_message(self, *a, **k): pass
print("listening on :5000", flush=True)
http.server.HTTPServer(("0.0.0.0", 5000), H).serve_forever()
""".strip()


def _load_env() -> None:
    for parent in Path(__file__).resolve().parents:
        env = parent / ".env"
        if env.is_file():
            for line in env.read_text().splitlines():
                if line and not line.startswith("#") and "=" in line:
                    k, v = line.split("=", 1)
                    os.environ.setdefault(k.strip(), v.strip())
            break
    required = (
        "AZURE_SUBSCRIPTION_ID", "ACA_RESOURCE_GROUP", "ACA_SANDBOX_GROUP",
        "ACA_SANDBOXGROUP_REGION",
        "ACA_CONNECTOR_GATEWAY", "ACA_CONNECTOR_CONNECTION",
        "ACA_CONNECTOR_GATEWAY_PRINCIPAL_ID",
    )
    missing = [k for k in required if not os.environ.get(k)]
    if missing:
        sys.exit(
            f"error: samples/.env missing {missing}.\n"
            "       Run:\n"
            "         python ../../../sandboxes/setup/python/setup.py\n"
            "         python ../../setup/python/setup.py"
        )


def _az_rest(method: str, url: str, body: dict | None = None,
             resource: str | None = None,
             check: bool = True,
             retry_on_5xx: int = 0) -> tuple[int, str, str]:
    cmd = ["az", "rest", "--method", method, "--url", url]
    if resource:
        cmd += ["--resource", resource]
    tmp = None
    if body is not None:
        fd, tmp = tempfile.mkstemp(prefix="aca-trig-lifecycle-", suffix=".json")
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(body, f)
        cmd += ["--body", f"@{tmp}"]
    try:
        attempt = 0
        while True:
            r = subprocess.run(cmd, capture_output=True, text=True,
                               shell=sys.platform == "win32")
            if r.returncode == 0:
                return r.returncode, r.stdout, r.stderr
            is_5xx = ("Internal Server Error" in (r.stderr or "")
                      or "InternalServerError" in (r.stderr or "")
                      or "Bad Gateway" in (r.stderr or "")
                      or "Service Unavailable" in (r.stderr or "")
                      or "Gateway Timeout" in (r.stderr or ""))
            if is_5xx and attempt < retry_on_5xx:
                backoff = 5 * (attempt + 1)
                print(f"    transient 5xx on {method} {url.split('?')[0]} - "
                      f"retrying in {backoff}s (attempt {attempt + 1}/{retry_on_5xx})")
                time.sleep(backoff)
                attempt += 1
                continue
            if check:
                sys.exit(
                    f"error: az rest {method} {url} failed (exit={r.returncode}):\n"
                    f"{r.stderr.strip()[:800]}"
                )
            return r.returncode, r.stdout, r.stderr
    finally:
        if tmp:
            try:
                os.unlink(tmp)
            except OSError:
                pass


# ---------- data-plane helpers ---------------------------------------------

def _dp_url(endpoint: str, sub: str, rg: str, sg: str,
            sandbox_id: str, suffix: str) -> str:
    """Build a sandbox data-plane URL against the regional endpoint
    (e.g. ``https://management.westus2.azuredevcompute.io``). Used for
    ports — the SDK's typed ``PortAuthEntraId`` doesn't carry
    ``objectIds`` today, so we hit the data plane (POST /ports/add)
    directly."""
    return (
        f"{endpoint}/subscriptions/{sub}"
        f"/resourceGroups/{rg}/sandboxGroups/{sg}/sandboxes/{sandbox_id}"
        f"/{suffix}?api-version={DATAPLANE_API_VERSION}"
    )


def _apply_ports(endpoint, sub, rg, sg, sandbox_id,
                 port: int, gw_principal: str, gw_tenant: str,
                 user_email: str) -> str:
    entra_id: dict = {"enabled": True, "objectIds": [gw_principal]}
    if gw_tenant:
        entra_id["tenantIds"] = [gw_tenant]
    if user_email and "@" in user_email:
        entra_id["emails"] = [user_email]
    body = {"port": port, "auth": {"entraId": entra_id}}
    url = _dp_url(endpoint, sub, rg, sg, sandbox_id, "ports/add")
    _, out, _ = _az_rest("POST", url, body=body, resource=DATAPLANE_RESOURCE)
    try:
        data = json.loads(out) if out else {}
    except json.JSONDecodeError:
        data = {}
    port_url = None
    if isinstance(data, dict):
        if isinstance(data.get("ports"), list):
            match = next((p for p in data["ports"]
                          if isinstance(p, dict) and p.get("port") == port), {})
            port_url = match.get("url")
        else:
            port_url = data.get("url")
    if not port_url:
        raise RuntimeError(f"ports/add returned no url: {data!r}")
    return port_url


def _remove_port(endpoint, sub, rg, sg, sandbox_id, port: int) -> None:
    url = _dp_url(endpoint, sub, rg, sg, sandbox_id, "ports/remove")
    _az_rest("POST", url, body={"port": port},
             resource=DATAPLANE_RESOURCE, check=False)


def main() -> int:
    _load_env()
    sub = os.environ["AZURE_SUBSCRIPTION_ID"]
    rg = os.environ["ACA_RESOURCE_GROUP"]
    sg = os.environ["ACA_SANDBOX_GROUP"]
    region = os.environ["ACA_SANDBOXGROUP_REGION"]
    gw = os.environ["ACA_CONNECTOR_GATEWAY"]
    conn = os.environ["ACA_CONNECTOR_CONNECTION"]
    gw_principal = os.environ["ACA_CONNECTOR_GATEWAY_PRINCIPAL_ID"]
    gw_tenant = os.environ.get("ACA_CONNECTOR_GATEWAY_TENANT_ID", "").strip()
    user_email = os.environ.get("ACA_USER_EMAIL", "").strip()

    arm_base = (
        f"https://management.azure.com/subscriptions/{sub}/resourceGroups/{rg}"
        f"/providers/Microsoft.Web/connectorGateways/{gw}"
    )
    config_name = "trigger-lifecycle-demo"

    # --- 1. Discover trigger operations -----------------------------------
    print("==> 1. Discovering trigger operations for office365...")
    _, gw_out, _ = _az_rest("GET", f"{arm_base}?api-version={API_VERSION}")
    # Prefer the gateway resource's own location (returned by the GET above).
    # Fall back to the explicit gateway region env var, then to the sandbox
    # region. Never hardcode a region default.
    location = (
        json.loads(gw_out).get("location")
        or os.environ.get("ACA_CONNECTOR_GATEWAY_REGION")
        or region
    )
    ops_url = (
        f"https://management.azure.com/subscriptions/{sub}/providers/"
        f"Microsoft.Web/locations/{location}/managedApis/office365/"
        f"apiOperations?api-version=2016-06-01"
    )
    _, ops_out, _ = _az_rest("GET", ops_url)
    ops = json.loads(ops_out).get("value", [])
    triggers = [op for op in ops if op.get("properties", {}).get("trigger")]
    print(f"    {len(triggers)} trigger operations available, e.g.:")
    for op in triggers[:5]:
        print(
            f"      - {op['name']}: "
            f"{op.get('properties', {}).get('summary', '')}"
        )
    op_name = next(
        (op["name"] for op in triggers if op["name"] == "OnNewEmailV3"),
        triggers[0]["name"] if triggers else "OnNewEmailV3",
    )
    print(f"    using: {op_name}")

    # --- 2. Sandbox + listener --------------------------------------------
    endpoint = endpoint_for_region(region)
    credential = DefaultAzureCredential()
    client = SandboxGroupClient(
        endpoint, credential,
        subscription_id=sub, resource_group=rg, sandbox_group=sg,
    )
    sandbox = None
    port_added = False
    trigger_created = False
    run_id = uuid.uuid4().hex[:8]

    try:
        print(f"==> 2. Creating sandbox in '{sg}' (labels.run={run_id})...")
        sandbox = client.begin_create_sandbox(
            disk="ubuntu",
            labels={"sample": "connector-trigger-lifecycle", "run": run_id},
        ).result()
        sid = sandbox.sandbox_id
        print(f"    sandbox: {sid}")

        print("==> Installing python3 (listener is stdlib only)...")
        r = sandbox.exec(
            "set -e; "
            "apt-get update -qq >/dev/null 2>&1 || true; "
            "DEBIAN_FRONTEND=noninteractive apt-get install -y -qq python3 ca-certificates >/dev/null 2>&1 || true; "
            "command -v python3",
        )
        if r.exit_code != 0:
            sys.exit(f"error: python3 install failed:\n{r.stderr or r.stdout}")

        print("==> Uploading + starting webhook listener on :5000...")
        sandbox.write_file("/app/server.py", WEBHOOK_SERVER)
        # Sandbox `executeShellCommand` reaps the process group when the
        # exec session ends. `nohup` alone (which only catches SIGHUP) is
        # NOT enough - we need `setsid` + `< /dev/null` + `disown` to fully
        # detach. See email-to-sandbox/python/run.py for the same pattern.
        launcher = (
            "#!/bin/bash\n"
            "set -u\n"
            "pkill -f 'python3 /app/server.py' 2>/dev/null || true\n"
            "sleep 1\n"
            "rm -f /tmp/wh.log /tmp/wh.pid\n"
            "setsid nohup python3 /app/server.py "
            "> /tmp/wh.log 2>&1 < /dev/null &\n"
            "disown || true\n"
            "echo $! > /tmp/wh.pid\n"
        )
        sandbox.write_file("/app/launch.sh", launcher)
        sandbox.exec("bash /app/launch.sh")

        # Readiness check - fail loudly if the listener never comes up.
        last_code = ""
        for _ in range(30):
            r = sandbox.exec(
                f"curl -fsS -o /dev/null -w '%{{http_code}}' -X POST "
                f"http://localhost:{PORT}/healthz || true",
            )
            last_code = (r.stdout or "").strip()
            if last_code == "200":
                break
            time.sleep(1)
        if last_code != "200":
            pid_diag = sandbox.exec(
                "if [ -f /tmp/wh.pid ]; then "
                "  pid=$(cat /tmp/wh.pid); "
                "  if kill -0 \"$pid\" 2>/dev/null; then echo \"pid $pid alive\"; "
                "  else echo \"pid $pid DEAD\"; fi; "
                "else echo 'no pid file'; fi"
            )
            log = sandbox.exec(
                "if [ -f /tmp/wh.log ]; then tail -c 4000 /tmp/wh.log; "
                "else echo '(no log file)'; fi"
            )
            sys.exit(
                f"error: listener not ready (last http_code={last_code!r}).\n"
                f"  {(pid_diag.stdout or '').strip()}\n"
                f"  /tmp/wh.log:\n{(log.stdout or '').strip() or '(empty)'}"
            )
        print("    listener is up (in-sandbox curl returns 200)")

        # --- 3. Port with entraId.objectIds (gateway MI) ------------------
        print(
            f"==> 3. add port {PORT} with entraId.objectIds=[gateway MI]"
        )
        # The SDK's add_port helper only supports anonymous OR a single
        # email. To add objectIds (or both emails + objectIds) we hit the
        # data plane POST /ports/add directly via az rest.
        port_url = _apply_ports(
            endpoint, sub, rg, sg, sid, PORT, gw_principal, gw_tenant, user_email,
        )
        port_added = True
        callback_url = port_url.rstrip("/") + "/webhook"
        print(f"    port URL:     {port_url}")
        print(f"    callback URL: {callback_url}")

        # --- 4. Create trigger config -------------------------------------
        print(f"==> 4. PUT trigger config '{config_name}'...")
        trigger_body = {
            "properties": {
                "state": "Enabled",
                "connectionDetails": {
                    "connectorName": "office365",
                    "connectionName": conn,
                },
                "metadata": {
                    "sandboxGroupName": sg,
                    "sandboxId": sid,
                    "recurrenceFrequency": "Minute",
                    "recurrenceInterval": 1,
                },
                "notificationDetails": {
                    "callbackUrl": callback_url,
                    "httpMethod": "POST",
                    # Gateway MSI authenticates the callback POST to the
                    # sandbox proxy. Without this the proxy returns 401.
                    "authentication": {
                        "type": "ManagedServiceIdentity",
                        "audience": "https://auth.adcproxy.io/",
                    },
                },
                "operationName": op_name,
                "parameters": [{"name": "folderPath", "value": "Inbox"}],
            }
        }
        _, t_out, _ = _az_rest(
            "PUT",
            f"{arm_base}/triggerConfigs/{config_name}?api-version={API_VERSION}",
            body=trigger_body,
            retry_on_5xx=3,
        )
        trigger_created = True
        try:
            state = json.loads(t_out).get("properties", {}).get("state", "?")
        except (json.JSONDecodeError, AttributeError):
            state = "?"
        print(f"    created (state={state})")

        # --- 5. List, disable, enable, delete -----------------------------
        print("==> 5. Listing trigger configs on this gateway...")
        _, l_out, _ = _az_rest(
            "GET", f"{arm_base}/triggerConfigs?api-version={API_VERSION}"
        )
        for t in json.loads(l_out).get("value", []):
            print(
                f"      - {t['name']}: "
                f"{t.get('properties', {}).get('state', '?')}"
            )

        print("==> Disabling the trigger config...")
        _az_rest(
            "POST",
            f"{arm_base}/triggerConfigs/{config_name}/disable"
            f"?api-version={API_VERSION}",
        )
        print("==> Re-enabling the trigger config...")
        _az_rest(
            "POST",
            f"{arm_base}/triggerConfigs/{config_name}/enable"
            f"?api-version={API_VERSION}",
        )

        print()
        print("==> Lifecycle demo complete.")
        print("    Cleaning up: trigger -> port -> sandbox (order matters).")
        return 0

    finally:
        # Cleanup order: trigger first (it holds an event subscription),
        # then port, then sandbox. Skipping the gateway / connection /
        # access policy - those live in the scenario baseline.
        if trigger_created:
            print("==> DELETE trigger config")
            _az_rest(
                "DELETE",
                f"{arm_base}/triggerConfigs/{config_name}"
                f"?api-version={API_VERSION}",
                check=False,
            )
        if sandbox is not None and port_added:
            try:
                print(f"==> remove_port({PORT})")
                _remove_port(endpoint, sub, rg, sg, sandbox.sandbox_id, PORT)
            except Exception as e:
                print(f"    warning: remove_port failed: {e}")
        if sandbox is not None:
            try:
                print(f"==> delete sandbox {sandbox.sandbox_id}")
                sandbox.delete()
            except Exception as e:
                print(f"    warning: delete sandbox failed: {e}")
        else:
            # Interrupted before begin_create_sandbox returned - sweep by label.
            print(f"==> Sweeping leaked sandboxes with run={run_id}...")
            try:
                for sbx in client.list_sandboxes(labels={"run": run_id}):
                    sid = getattr(sbx, "id", None) or getattr(sbx, "sandbox_id", None)
                    if not sid:
                        continue
                    try:
                        client.delete_sandbox(sid)
                        print(f"    deleted leaked sandbox {sid}")
                    except Exception as e:
                        print(f"    warning: failed to delete {sid}: {e}")
            except Exception as e:
                print(f"    warning: sweep failed: {e}")
        client.close()
        credential.close()


if __name__ == "__main__":
    sys.exit(main())
