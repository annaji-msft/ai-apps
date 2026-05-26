# excalidraw-anonymous — public MCP server in a sandbox

Host [`excalidraw-mcp`](https://github.com/excalidraw/excalidraw-mcp)
inside an ACA sandbox and expose it at a public, anonymous URL.
Connect from VS Code Copilot Chat, Claude Desktop, ChatGPT Connectors,
or this Copilot CLI — ask your AI to draw a diagram and it renders
inline in chat.

> Part of [scenarios/08-mcp-hosting](../README.md). See the sibling
> pattern [`dab-sql-devtunnel`](../dab-sql-devtunnel/) for the
> no-inbound-port variant.

## What it does

1. Creates a sandbox on the `copilot` disk (Node 24 is needed by
   `excalidraw-mcp`; the `copilot` disk includes a modern Node toolchain).
2. Clones, installs, and builds `excalidraw-mcp` inside the sandbox.
3. Starts the server on port `80` as a background process.
4. Polls in-sandbox readiness on `POST /mcp` with an MCP `initialize`
   request — no `sleep N` guesses.
5. Calls `add_port(80, anonymous=True)` → public
   `https://<sandbox-id>--80.proxy.azuredevcompute.io/mcp`.
6. Verifies the public URL with a real MCP `initialize` handshake
   (host side, over HTTPS).
7. Prints copy-pasteable config snippets for the major MCP clients.

The sandbox stays running after the script verifies success. Press
Enter at the prompt to tear it down (port removed → sandbox deleted).

## Run it

```bash
cd python
pip install -r requirements.txt
python run.py
```

## What you can do with it

Once the URL is in your MCP client, ask your AI in normal chat:

- *"Draw an architecture diagram of a 3-tier web app with a load
  balancer, two app servers, and a Postgres database."*
- *"Add a Redis cache between the app tier and the DB."*
- *"Export the current scene as SVG."*

The diagram renders inline. State persists in the sandbox — restart
your IDE and the scene is still there.

## Verify it works

The script already proves the endpoint is up by running an MCP
`initialize` handshake over HTTPS. To chat with it for real, pick one:

### From this Copilot CLI session

After the URL is printed, ask me:

> "Register the MCP server at `<URL>` for this session and list its
> tools, then call `create_element` to draw a rectangle."

I'll add it to the CLI's MCP config and you'll see the tools immediately.

### From VS Code Copilot Chat

Add to `.vscode/mcp.json` in your repo:

```json
{
  "servers": {
    "excalidraw": {
      "type": "http",
      "url": "https://<sandbox-id>--80.proxy.azuredevcompute.io/mcp"
    }
  }
}
```

Reload VS Code → the excalidraw tools appear in Copilot Chat's tool
picker.

### From Claude Desktop / ChatGPT

Settings → Connectors → Add custom connector → paste the URL.

## Production tips

- **Anonymous = open to the internet.** Anyone with the URL can draw on
  your board and consume its memory. Fine for an ephemeral demo, not
  for anything user-facing. For Entra-gated exposure use
  `add_port(80, email=...)` (see [guide 06](../../../guides/06-ports/README.md)).
- **Bake the disk.** [Guide 03 (disks)](../../../guides/03-disks/README.md)
  — pre-install Node 24 + a built `excalidraw-mcp` so each cold start
  skips `npm install` and `npm run build`.
- **Snapshot post-build.** [Guide 02 (snapshots)](../../../guides/02-snapshots/README.md)
  — resume into a fully built MCP server in ~1s instead of ~90s.
- **Auto-suspend.** [Guide 05 (lifecycle)](../../../guides/05-lifecycle/README.md)
  — idle MCP sandboxes shouldn't burn quota; suspend on inactivity and
  resume on the next request.
- **One sandbox per user.** [Guide 11 (labels)](../../../guides/11-labels/README.md)
  — tag with `{"user": "alice@…"}` and look up with
  `list_sandboxes(labels=…)` so each user gets their own drawing surface.

## Layout

```
excalidraw-anonymous/
├── README.md           ← this file
└── python/
    ├── README.md
    ├── requirements.txt
    └── run.py
```
