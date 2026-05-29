# Local dev for the document-automation listener

The listener that runs inside the sandbox (`../host/listener.py`) is
a plain FastAPI app — you can run it locally to iterate on the
prompt / Copilot invocation without re-deploying the sandbox every
time.

## Prereqs

- `python>=3.10`
- `copilot` CLI installed locally (same one the sandbox uses)
- `poppler-utils`, `tesseract-ocr` (for OCR — `brew install` on macOS,
  `apt install` on Linux, `choco install` on Windows)
- A working Connector Gateway + SharePoint MCP server (i.e., you ran
  `azd up` for this scenario at least once). The gateway issues the
  MCP API key + provides the MCP URL.
- A GitHub PAT with Copilot / Models access.

## Run the listener locally

```bash
cd samples/sandboxes/scenarios/11-connectors-document-automation/host
python -m venv .venv
source .venv/bin/activate    # Windows: .venv\Scripts\Activate.ps1
pip install -r requirements.txt

# Pull the gateway URL + key out of your azd env
azd env get-values --cwd .. | grep -E '(SHAREPOINT|GATEWAY)'

export SHAREPOINT_MCP_URL='https://.../mcp'      # from postdeploy.py output
export SHAREPOINT_SITE_URL='https://contoso.sharepoint.com/teams/Finance'
export SHAREPOINT_LIBRARY_ID='<library-guid>'
export SHAREPOINT_OUTPUT_FOLDER='Extracted'
export COPILOT_GITHUB_TOKEN='ghp_...'

uvicorn listener:app --host 0.0.0.0 --port 8080
```

## Send a fake trigger

```bash
curl -X POST http://localhost:8080/ \
     -H 'Content-Type: application/json' \
     --data @samples/sample-file-properties.json
```

The listener will:
1. Boot a per-request workspace under `/work/<run-id>/` (Linux) or
   `%TEMP%\work\<run-id>` (Windows).
2. Run Copilot CLI with `--allow-all-tools` against `prompt.md`,
   pointing it at the SharePoint MCP server.
3. Copilot fetches the (mock) file, OCRs / parses it, emits JSON,
   uploads result back to SharePoint.

Watch listener stdout for the per-run logs.

## Notes

- The egress proxy that stamps the gateway API key on outbound MCP
  calls does NOT run locally. The local listener sends MCP requests
  with no auth header — you must adapt to either (a) include the
  API key inline in the MCP URL via your local `.mcp.json` (most
  MCP clients support `?api-key=...` query params), or (b) set up a
  local mitmproxy that stamps the header.
- The whole point of running locally is iterating on the prompt
  + Copilot invocation. For the end-to-end "gateway trigger fires
  per real SharePoint upload" flow, use the deployed sandbox — the
  trigger has no equivalent "deliver to localhost" mode.
- Quick re-deploy of just the listener (no full `azd up` cycle):
  ```bash
  # from the scenario folder
  python infra/scripts/postdeploy.py --skip-oauth
  ```
  This re-uploads `host/*` into the existing sandbox and restarts
  uvicorn without re-running the OAuth consents.
