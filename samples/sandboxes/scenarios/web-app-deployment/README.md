# Scenario: Web app deployment

Deploy a tiny Node.js HTTP server inside a sandbox and hit it from the
public internet.

Composes three primitives from `guides/`:

- **Files** ([guide 02](../../guides/02-files)) - upload the app source
- **Exec** ([guide 01](../../guides/01-sandboxes)) - start the server
- **Ports** ([guide 03](../../guides/03-ports)) - publish port 8080

- [`python/`](python/) - Python SDK
- [`cli/`](cli/) - `aca` CLI (bash)

## What it does

1. Boot a sandbox from the `node-22` disk image
2. Upload `index.js` (a Node.js HTTP server) to `/app/`
3. Start it in the background with `nohup`
4. Expose port 8080 anonymously
5. Fetch the public URL from your local machine and verify the JSON
   response
6. Tear everything down

## Production tips

- **Pick a region close to your users.** The public port URL is served
  from the same region as your sandbox group. If you need multi-region,
  create one sandbox group per region.
- **Per-tenant isolation = per-sandbox.** A sandbox is a VM, not a
  container. Use one sandbox per tenant/user/job and lean on
  `add_port(anonymous=True)` for the public URL only when you want
  unauthenticated access. Pass `email=...` for SSO-gated URLs instead.
- **Snapshot before risky operations.** If your app installs packages
  or fetches model weights, snapshot once and boot future sandboxes
  from the snapshot to skip the warm-up cost. See
  [`guides/04-snapshots`](../../guides/04-snapshots).
- **Lifecycle policy controls cost.** Set
  `AutoSuspendPolicy(enabled=True, interval=600)` to suspend idle
  sandboxes - they wake on the next request.
- **Don't put long-running production traffic on sandboxes.** They are
  optimized for AI-agent and per-task workloads. For 24/7 services,
  the `containerapps/` pillar (Phase 4) is the better fit.
