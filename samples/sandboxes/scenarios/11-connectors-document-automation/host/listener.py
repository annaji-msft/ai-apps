"""host_listener — FastAPI app running inside the host sandbox.

The Connector Gateway's "When a file is created (properties only)"
trigger POSTs directly to this listener (via the ADC proxy URL
``https://<sandboxId>--8080.<region>.adcproxy.io``). The proxy has
already validated that the caller is the gateway MI; we trust the
trust boundary at the proxy and just process the payload.

Per request (one invoice PDF):

  1. Receive the SharePoint file metadata (id, name, path, ...) in
     the request body. The trigger config sends only the
     `dynamicProperties` block from the upstream event, NOT the full
     event envelope.
  2. Allocate a fresh per-run workspace at /work/<run-id>/.
  3. Build a prompt for Copilot CLI that instructs it to:
       a. Call the SharePoint MCP `GetFileContent` (or equivalent)
          tool with the file id, save the bytes to /work/.../input.pdf
       b. Run `pdftotext` / `tesseract` to extract text.
       c. Reason over the text + emit a normalized invoice JSON.
       d. Call the SharePoint MCP `UploadFile` (or equivalent) tool
          to drop the result JSON into the /Invoices/Extracted folder.
  4. Run Copilot CLI non-interactively with the prompt.
  5. Return 200 to the gateway. Cleanup is best-effort.

Egress: the sandbox's egress policy (applied at boot by the
post-deploy script) is deny-default + Transform rules that stamp
X-API-Key on outbound MCP calls + Authorization on GitHub Copilot
hosts. The sandbox itself holds NO MCP api key.
"""

from __future__ import annotations

import asyncio
import logging
import os
import subprocess
import sys
import uuid
from pathlib import Path
from typing import Any

from fastapi import FastAPI, HTTPException, Request, Response

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s :: %(message)s",
    stream=sys.stdout,
)
log = logging.getLogger("listener")

# ---- Configuration (populated by bootstrap.sh via env) ----------------------

# The runtime URL of the SharePoint MCP server on the gateway. Set
# at sandbox-bootstrap time by the post-deploy script (which reads it
# from the mcpserverConfig data plane after the gateway is provisioned).
SHAREPOINT_MCP_URL = os.environ["SHAREPOINT_MCP_URL"]

# The SharePoint document library / folder where extracted result
# JSONs should land. Pinned into the prompt so Copilot doesn't have
# to guess. Both passed in as plain env vars at bootstrap time.
SHAREPOINT_SITE_URL = os.environ.get("SHAREPOINT_SITE_URL", "").strip()
SHAREPOINT_LIBRARY_ID = os.environ.get("SHAREPOINT_LIBRARY_ID", "").strip()
SHAREPOINT_OUTPUT_FOLDER = os.environ.get("SHAREPOINT_OUTPUT_FOLDER", "Extracted").strip()

# Copilot CLI MUST have a GitHub credential in its env before it
# attempts any network call (see scenario 10 notes — its auth error
# fires before the egress proxy can intervene). Provided by the
# bootstrap script as a sandbox env var (NOT a sandbox secret —
# sandboxes don't currently expose secret refs, only env). The egress
# proxy ALSO has a Transform rule stamping Authorization on api.github.com
# and the two githubcopilot.com hosts as defense-in-depth.
COPILOT_GITHUB_TOKEN = os.environ.get("COPILOT_GITHUB_TOKEN", "").strip()

PROMPT_TEMPLATE = Path(__file__).with_name("prompt.md").read_text(encoding="utf-8")

app = FastAPI(title="sandboxes-connectors-document-automation listener")

# Background tasks. Same pattern as scenario 10's receiver — we ack
# the gateway fast so it doesn't retry, then do the long-running work
# in a task. Keep a set so the asyncio task isn't GC'd prematurely.
_inflight: set[asyncio.Task[Any]] = set()


@app.get("/")
def root() -> dict[str, Any]:
    return {
        "service": "sandboxes-connectors-document-automation",
        "status": "ok",
        "sharepoint_mcp_configured": bool(SHAREPOINT_MCP_URL),
    }


@app.get("/healthz")
def healthz() -> Response:
    # Used by the bootstrap script to wait for uvicorn to come up
    # before declaring the sandbox ready for trigger registration.
    return Response(status_code=200)


@app.post("/")
@app.post("/trigger")
async def trigger(request: Request) -> dict[str, Any]:
    """Entry point for the Connector Gateway trigger.

    The trigger config's `notificationDetails.body` is
    ``@{triggerBody()?['dynamicProperties']}``, so the body here is
    just the SharePoint file's `dynamicProperties` block — typically
    something like::

        {
          "ID": 42,
          "FileLeafRef": "invoice-2026-001.pdf",
          "FileRef": "/teams/.../Invoices/Inbox/invoice-2026-001.pdf",
          "{Identifier}": "%252fteams%252f...%252finvoice-2026-001.pdf",
          ...
        }

    Different SharePoint libraries / trigger filters may shape this
    slightly differently. We pass the whole blob to Copilot in the
    prompt so the model can navigate it.
    """
    # Always log the raw body + content-type for diagnostics. The
    # gateway sometimes sends a slightly different shape than we
    # expect (e.g., wrapped in `triggerBody()` envelope, or empty
    # for keep-alive pokes).
    raw = await request.body()
    ctype = request.headers.get("content-type", "<none>")
    log.info("trigger POST: content-type=%s len=%d", ctype, len(raw))
    if not raw:
        log.warning("trigger POST: empty body — likely a gateway probe; acking 200")
        return {"accepted": "empty"}
    preview = raw[:1500].decode("utf-8", "replace")
    log.info("trigger POST body preview:\n%s", preview)
    try:
        import json as _json
        payload = _json.loads(raw)
    except Exception as exc:
        log.warning("trigger POST: JSON parse failed (%s); acking 200 so the gateway doesn't retry", exc)
        return {"accepted": "non-json"}

    run_id = uuid.uuid4().hex[:8]
    log.info("[%s] trigger received: top-level keys=%s", run_id, sorted(payload.keys())[:12] if isinstance(payload, dict) else f"<{type(payload).__name__}>")

    task = asyncio.create_task(_process_one(payload, run_id))
    _inflight.add(task)
    task.add_done_callback(_inflight.discard)

    return {"accepted": run_id}


async def _process_one(file_props: dict[str, Any], run_id: str) -> None:
    """Run Copilot CLI against this one file's properties.

    Workspace is /work/<run-id>/ so concurrent runs (if the gateway
    delivers a batch) don't trample each other. The agent is told to
    confine its file I/O to that workspace.
    """
    # Self-loop guard: the gateway also fires for the JSON files
    # WE upload to the /Extracted folder. Skip anything whose path
    # is inside the output folder or whose name ends with `.json`
    # (our own results). Check the common SharePoint path fields.
    out_folder = (SHAREPOINT_OUTPUT_FOLDER or "Extracted").strip("/")
    file_ref = str(file_props.get("FileRef", "") or "")
    identifier = str(file_props.get("{Identifier}", "") or "")
    leaf = str(file_props.get("FileLeafRef", "") or "")
    is_own_output = (
        f"/{out_folder}/" in file_ref
        or f"%252f{out_folder}%252f" in identifier  # url-encoded
        or f"%2f{out_folder}%2f" in identifier
        or leaf.lower().endswith(".json")
    )
    if is_own_output:
        log.info(
            "[%s] skipping file (recognized as our own output / in %s folder): leaf=%r ref=%r",
            run_id, out_folder, leaf, file_ref[:120],
        )
        return

    workspace = Path("/work") / run_id
    workspace.mkdir(parents=True, exist_ok=True)
    try:
        prompt = _render_prompt(file_props, run_id, workspace)
        (workspace / "prompt.md").write_text(prompt, encoding="utf-8")

        # Drop the MCP config inside the workspace so the prompt can
        # `cd` into the workspace and run copilot — Copilot v1 reads
        # `./.mcp.json` (workspace-level) in addition to its global
        # ~/.copilot/mcp-config.json. We use the workspace-level file
        # so each run can theoretically swap MCP servers in/out without
        # touching global config.
        _write_mcp_config(workspace)

        await _run_copilot(workspace, run_id)
        log.info("[%s] done", run_id)
    except Exception as exc:  # noqa: BLE001
        log.exception("[%s] processing failed: %s", run_id, exc)
    finally:
        # Best-effort cleanup. Leave the prompt + result files on
        # disk for ~hours so an operator can inspect after the fact;
        # a future cleanup loop can prune /work/* older than N hours.
        pass


def _render_prompt(file_props: dict[str, Any], run_id: str, workspace: Path) -> str:
    sharepoint_target = ""
    if SHAREPOINT_SITE_URL:
        # Split site URL into hostname + server-relative path so the
        # prompt can show the agent exactly what to feed getSiteByPath.
        from urllib.parse import urlparse
        u = urlparse(SHAREPOINT_SITE_URL)
        host = u.netloc
        srv_path = u.path.lstrip("/")
        sharepoint_target = (
            "\n"
            f"- site URL:        {SHAREPOINT_SITE_URL}\n"
            f"  hostname:        {host}\n"
            f"  serverRelative:  {srv_path}\n"
        )
        if SHAREPOINT_LIBRARY_ID:
            sharepoint_target += (
                f"- library list ID (from trigger): {SHAREPOINT_LIBRARY_ID}\n"
                "  (this is the SharePoint LIST id; the MCP tools want the\n"
                "   DRIVE id which you get from listDocumentLibrariesInSite — pick\n"
                "   whichever document library matches your scenario, typically\n"
                "   the first or only one in the site if this site has just one.)\n"
            )
        sharepoint_target += (
            f"- output folder:   {SHAREPOINT_OUTPUT_FOLDER}\n"
        )
    file_props_pretty = _safe_pretty(file_props, max_chars=4000)
    return PROMPT_TEMPLATE.format(
        run_id=run_id,
        workspace=str(workspace),
        file_props=file_props_pretty,
        sharepoint_target=sharepoint_target,
    )


def _write_mcp_config(workspace: Path) -> None:
    # Copilot CLI v1.x reads MCP server config from `./.mcp.json`
    # (workspace-level) and `~/.copilot/mcp-config.json` (user-level).
    # We write the workspace-level file to keep each run self-contained.
    # Top-level key is `mcpServers` (camelCase). The egress proxy adds
    # X-API-Key on the way out so the URL here is the bare gateway URL.
    mcp_json = (
        '{\n'
        '  "mcpServers": {\n'
        '    "sharepoint": {\n'
        '      "type": "http",\n'
        f'      "url": "{SHAREPOINT_MCP_URL}"\n'
        '    }\n'
        '  }\n'
        '}\n'
    )
    (workspace / ".mcp.json").write_text(mcp_json, encoding="utf-8")


def _safe_pretty(obj: Any, *, max_chars: int) -> str:
    import json
    try:
        s = json.dumps(obj, indent=2, default=str)
    except Exception:
        s = repr(obj)
    if len(s) > max_chars:
        s = s[:max_chars] + "\n... (truncated)"
    return s


async def _run_copilot(workspace: Path, run_id: str) -> None:
    log.info("[%s] running copilot in %s", run_id, workspace)
    env = os.environ.copy()
    if COPILOT_GITHUB_TOKEN:
        env["COPILOT_GITHUB_TOKEN"] = COPILOT_GITHUB_TOKEN

    # Diagnostic — log copilot version + the MCP server registration
    # before the real run, like scenario 10 does.
    for cmd in ("copilot --version", "copilot mcp list"):
        try:
            r = await _run("/bin/bash", "-lc", cmd, cwd=workspace, env=env, timeout=15)
            log.info("[%s] %s: %s", run_id, cmd, (r.stdout or "").strip()[:500])
        except Exception as exc:  # noqa: BLE001
            log.warning("[%s] %s failed: %s", run_id, cmd, exc)

    prompt_path = workspace / "prompt.md"
    r = await _run(
        "/bin/bash", "-lc",
        f'copilot --allow-all-tools -p "$(cat {prompt_path})" 2>&1',
        cwd=workspace, env=env, timeout=360,
    )
    log.info(
        "[%s] copilot exit=%d\nstdout:\n%s\n[--- end stdout ---]",
        run_id, r.returncode, (r.stdout or ""),
    )
    if r.returncode != 0:
        raise RuntimeError(f"copilot run failed exit={r.returncode}")


class _ProcResult:
    __slots__ = ("returncode", "stdout", "stderr")
    def __init__(self, returncode: int, stdout: str, stderr: str) -> None:
        self.returncode = returncode
        self.stdout = stdout
        self.stderr = stderr


async def _run(
    *cmd: str, cwd: Path, env: dict[str, str], timeout: float,
) -> _ProcResult:
    """Run a subprocess with a timeout. Captures stdout+stderr together."""
    proc = await asyncio.create_subprocess_exec(
        *cmd,
        cwd=str(cwd),
        env=env,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.STDOUT,
    )
    try:
        out_b, _ = await asyncio.wait_for(proc.communicate(), timeout=timeout)
    except asyncio.TimeoutError:
        proc.kill()
        await proc.wait()
        raise RuntimeError(f"command {cmd!r} exceeded timeout={timeout}s")
    return _ProcResult(proc.returncode or 0, out_b.decode("utf-8", "replace"), "")


# Local dev entrypoint
if __name__ == "__main__":
    import uvicorn  # noqa: E402

    uvicorn.run(app, host="0.0.0.0", port=8080)
