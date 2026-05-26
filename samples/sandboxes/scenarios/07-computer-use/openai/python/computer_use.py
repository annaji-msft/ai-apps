"""Computer-use agent in an ACA sandbox, driven by Azure OpenAI.

End-to-end demo:

  1. Boot a fresh ``ubuntu`` sandbox under deny-by-default egress (the agent
     never reaches the internet — it only talks to the sandbox-local form).
  2. Upload ``desktop-image/`` (setup.sh + control_server.py + form/) into the
     sandbox and run ``setup.sh`` to bring up Xvfb + Chromium + noVNC +
     the FastAPI control server.
  3. Expose port 7000 (control) and 6080 (noVNC) via ``add_port``. Print the
     noVNC URL so the operator can watch the agent work in their browser.
  4. Run the OpenAI Responses API ``computer_use_preview`` loop against an
     Azure OpenAI deployment of the ``computer-use-preview`` model.
  5. Verify the form submission landed in ``/tmp/submission.json`` inside
     the sandbox and print the totals.
  6. Delete the sandbox.

Configuration (samples/.env):
  AZURE_SUBSCRIPTION_ID, ACA_RESOURCE_GROUP, ACA_SANDBOX_GROUP,
  ACA_SANDBOXGROUP_REGION  -- the sandbox group (from setup.py)
  AZURE_OPENAI_ENDPOINT    -- e.g. https://my-aoai.openai.azure.com/
  AZURE_OPENAI_API_KEY     -- key for that endpoint
  AZURE_OPENAI_COMPUTER_USE_DEPLOYMENT  -- deployment name, e.g. "computer-use-preview"
  AZURE_OPENAI_API_VERSION (optional)   -- defaults to a current preview
"""

from __future__ import annotations

import base64
import json
import os
import sys
import time
import uuid
from pathlib import Path

from azure.identity import DefaultAzureCredential
from azure.containerapps.sandbox import (
    SandboxGroupClient,
    endpoint_for_region,
)
from openai import AzureOpenAI

from aca_computer import ACAComputer

# --------------------------------------------------------------------------
# Tunables
# --------------------------------------------------------------------------

DEFAULT_API_VERSION = "2025-04-01-preview"
DISPLAY_W, DISPLAY_H = 1280, 800
MAX_AGENT_TURNS = 30
CONTROL_PORT = 7000
NOVNC_PORT = 6080

DESKTOP_DIR = Path(__file__).resolve().parents[2] / "desktop-image"

TASK_PROMPT = """\
You are filling out an expense report for a business trip on the web form
already open in front of you (a Chromium window at http://localhost:8080).

Use the following data:

  Trip name:        Q4 customer visit - Seattle
  Start date:       2025-11-10
  End date:         2025-11-12
  Business purpose: Onsite design review with the Acme platform team
  Line items:
    - Airfare,          "SEA <-> JFK round-trip",  642.18
    - Hotel,            "Westin Seattle 2 nights", 489.00
    - Meals,            "Team dinner Tuesday",     127.55
    - Ground transport, "Airport taxi both ways",   84.40

Fill every field, add line items as needed (the form starts with one empty
row -- use the "Add line item" button for the others), then click
"Submit expense report". When you see the green "Submitted." confirmation,
the task is complete.
"""


# --------------------------------------------------------------------------
# Env loading (matches AGENTS.md idiom)
# --------------------------------------------------------------------------

def _load_env() -> None:
    for parent in Path(__file__).resolve().parents:
        env = parent / ".env"
        if env.is_file():
            for line in env.read_text().splitlines():
                if line and not line.startswith("#") and "=" in line:
                    k, v = line.split("=", 1)
                    os.environ.setdefault(k.strip(), v.strip())
            break
    missing = [k for k in (
        "ACA_SANDBOXGROUP_REGION", "AZURE_SUBSCRIPTION_ID",
        "ACA_RESOURCE_GROUP", "ACA_SANDBOX_GROUP",
        "AZURE_OPENAI_ENDPOINT", "AZURE_OPENAI_API_KEY",
        "AZURE_OPENAI_COMPUTER_USE_DEPLOYMENT",
    ) if not os.environ.get(k)]
    if missing:
        sys.exit(
            "error: missing env vars: " + ", ".join(missing) + "\n"
            "       Set them in samples/.env. Sandbox group keys come from\n"
            "       samples/sandboxes/setup/python/setup.py; Azure OpenAI keys\n"
            "       you set manually."
        )


# --------------------------------------------------------------------------
# Sandbox bootstrap
# --------------------------------------------------------------------------

def _upload_desktop_image(sandbox) -> None:
    """Write every file in desktop-image/ to /opt/desktop in the sandbox."""
    print(f"==> Uploading desktop image from {DESKTOP_DIR}...")
    sandbox.exec("mkdir -p /opt/desktop/form")
    for src in DESKTOP_DIR.rglob("*"):
        if src.is_dir():
            continue
        rel = src.relative_to(DESKTOP_DIR).as_posix()
        dest = f"/opt/desktop/{rel}"
        data = src.read_bytes()
        # write_file is the documented API for pushing files in
        sandbox.write_file(dest, data)
    sandbox.exec("chmod +x /opt/desktop/setup.sh")


def _install_desktop(sandbox) -> None:
    print("==> Installing desktop (this takes 2-4 minutes the first time)...")
    r = sandbox.exec("bash /opt/desktop/setup.sh", timeout=600)
    sys.stdout.write(r.stdout or "")
    if r.exit_code != 0:
        sys.stderr.write(r.stderr or "")
        raise RuntimeError(f"setup.sh failed with exit {r.exit_code}")


def _expose(sandbox, port: int, label: str) -> str:
    p = sandbox.add_port(port, anonymous=True)
    url = getattr(p, "url", None)
    if not url:
        raise RuntimeError(f"add_port({port}) returned no URL")
    print(f"    {label:<7} : {url}")
    return url


# --------------------------------------------------------------------------
# Agent loop
# --------------------------------------------------------------------------

def _tool_def() -> dict:
    return {
        "type": "computer_use_preview",
        "display_width": DISPLAY_W,
        "display_height": DISPLAY_H,
        "environment": "linux",
    }


def _extract_calls(response) -> list:
    return [item for item in (response.output or [])
            if getattr(item, "type", None) == "computer_call"]


def _extract_text(response) -> str:
    parts: list[str] = []
    for item in (response.output or []):
        if getattr(item, "type", None) == "message":
            for c in getattr(item, "content", None) or []:
                text = getattr(c, "text", None)
                if text:
                    parts.append(text)
    return "\n".join(parts).strip()


def _ack_safety_checks(call) -> list:
    """Acknowledge any pending_safety_checks the model asked us to confirm.

    For this demo the workload is fully isolated (deny-default egress, fresh
    ephemeral desktop, no creds), so we acknowledge them automatically.
    In production you'd surface them to a human.
    """
    raw = getattr(call, "pending_safety_checks", None) or []
    acks = []
    for sc in raw:
        if isinstance(sc, dict):
            acks.append(sc)
        else:
            acks.append({
                "id": getattr(sc, "id", None),
                "code": getattr(sc, "code", None),
                "message": getattr(sc, "message", None),
            })
    return acks


def run_agent(client: AzureOpenAI, deployment: str, computer: ACAComputer) -> str:
    """Drive the Responses API loop. Returns the agent's final text reply."""
    tool = _tool_def()
    print("==> Sending initial prompt to model...")
    response = client.responses.create(
        model=deployment,
        tools=[tool],
        input=[{"role": "user", "content": TASK_PROMPT}],
        reasoning={"summary": "concise"},
        truncation="auto",
    )

    for turn in range(1, MAX_AGENT_TURNS + 1):
        calls = _extract_calls(response)
        if not calls:
            return _extract_text(response) or "(no final message)"
        call = calls[0]
        action = getattr(call, "action", None)
        action_type = getattr(action, "type", None) if action else None
        print(f"    turn {turn:>2}: action={action_type}")

        # Execute the action against the sandbox desktop.
        try:
            computer.execute(action)
        except Exception as e:  # noqa: BLE001
            print(f"    [error] executing {action_type}: {e}")

        # Always send a fresh screenshot back as the call output.
        time.sleep(0.4)  # let the screen settle
        screenshot_b64 = computer.screenshot()

        response = client.responses.create(
            model=deployment,
            tools=[tool],
            previous_response_id=response.id,
            input=[{
                "call_id": call.call_id,
                "type": "computer_call_output",
                "acknowledged_safety_checks": _ack_safety_checks(call),
                "output": {
                    "type": "input_image",
                    "image_url": f"data:image/png;base64,{screenshot_b64}",
                },
            }],
            truncation="auto",
        )

    return "[stopped] hit MAX_AGENT_TURNS without the model emitting a final message"


# --------------------------------------------------------------------------
# Verification
# --------------------------------------------------------------------------

def _verify(sandbox) -> None:
    print("==> Verifying /tmp/submission.json...")
    try:
        raw = sandbox.read_file("/tmp/submission.json")
    except Exception as e:  # noqa: BLE001
        raise RuntimeError(f"no submission found: {e}")
    text = raw.decode() if isinstance(raw, (bytes, bytearray)) else raw
    data = json.loads(text)
    items = data.get("items", [])
    total = data.get("total", 0)
    print(f"    trip:   {data.get('trip_name')!r}")
    print(f"    items:  {len(items)}")
    for it in items:
        print(f"      - {it.get('category'):<18} ${float(it.get('amount', 0)):>8.2f}  {it.get('description')}")
    print(f"    total:  ${float(total):.2f}")
    print("    [ok] form submission recorded")


# --------------------------------------------------------------------------
# main
# --------------------------------------------------------------------------

def main() -> int:
    _load_env()
    region = os.environ["ACA_SANDBOXGROUP_REGION"]
    sub = os.environ["AZURE_SUBSCRIPTION_ID"]
    rg = os.environ["ACA_RESOURCE_GROUP"]
    sg = os.environ["ACA_SANDBOX_GROUP"]
    deployment = os.environ["AZURE_OPENAI_COMPUTER_USE_DEPLOYMENT"]

    run_id = uuid.uuid4().hex[:8]
    credential = DefaultAzureCredential()
    client = SandboxGroupClient(
        endpoint_for_region(region),
        credential,
        subscription_id=sub,
        resource_group=rg,
        sandbox_group=sg,
    )
    aoai = AzureOpenAI(
        azure_endpoint=os.environ["AZURE_OPENAI_ENDPOINT"],
        api_key=os.environ["AZURE_OPENAI_API_KEY"],
        api_version=os.environ.get("AZURE_OPENAI_API_VERSION", DEFAULT_API_VERSION),
    )

    sandbox = None
    try:
        print(f"==> Booting sandbox (run={run_id})...")
        # 4 GB / 2 vCPU is comfortable for Chromium + Xvfb + a control server.
        sandbox = client.begin_create_sandbox(
            disk="ubuntu",
            cpu="2000m",
            memory="4096Mi",
            labels={"scenario": "computer-use", "vendor": "openai", "run": run_id},
        ).result()
        print(f"    sandbox: {sandbox.sandbox_id}")

        _upload_desktop_image(sandbox)
        _install_desktop(sandbox)

        print("==> Exposing ports...")
        control_url = _expose(sandbox, CONTROL_PORT, "control")
        novnc_url = _expose(sandbox, NOVNC_PORT, "noVNC")

        # Lock down egress: deny by default. The agent talks only to
        # localhost (the form + control server) -- no internet needed.
        # The operator (this script) reaches the control server via the
        # ACA-minted public URL, which is ingress, not the sandbox's egress.
        print("==> Locking egress: default = Deny (no allow rules)...")
        sandbox.set_egress_default("Deny")

        print()
        print("=" * 72)
        print(f"  Watch the agent work in your browser:")
        print(f"    {novnc_url}/vnc.html?autoconnect=1&resize=remote")
        print("=" * 72)
        print()

        computer = ACAComputer(base_url=control_url, dimensions=(DISPLAY_W, DISPLAY_H))
        computer.wait_until_ready(timeout=90)

        final = run_agent(aoai, deployment, computer)
        print()
        print("==> Agent finished.")
        if final:
            print("--- final assistant message ---")
            print(final)
            print("-------------------------------")

        _verify(sandbox)
        return 0
    finally:
        if sandbox is not None:
            print(f"==> Deleting sandbox {sandbox.sandbox_id}...")
            try:
                sandbox.delete()
            except Exception as e:  # noqa: BLE001
                print(f"    warning: delete failed: {e}")
        else:
            print(f"==> Sweeping any leaked sandboxes with run={run_id}...")
            try:
                for s in client.list_sandboxes(labels={"run": run_id}):
                    try:
                        client.delete_sandbox(s.id)
                    except Exception:
                        pass
            except Exception as e:  # noqa: BLE001
                print(f"    warning: sweep failed: {e}")
        client.close()
        credential.close()


if __name__ == "__main__":
    sys.exit(main())
