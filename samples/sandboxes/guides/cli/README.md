# CLI deep dive

Capabilities of the `aca` CLI that aren't covered by the functional guides ([00 – 13](../)). This is reference material — each section is independent and self‑contained, so jump to whichever one you need.

> Verified against `aca 1.0.0-beta.1`. Every command and output block was executed before being pasted.

## Contents

- [Auth](#auth) — log in, switch subscriptions, delegated `az login`
- [Help commands](#help-commands) — discover everything from the terminal
- [Config deep dive](#config-deep-dive) — `~/.aca/config.json`, Shared vs Sandbox, precedence
- [`doctor`](#doctor) — the 8-check readiness probe
- [YAML spec workflow](#yaml-spec-workflow) — `init` → `schema` → `validate` → `apply`
- [Selectors](#selectors) — `--id` vs `--selector "k=v,k2=v2"`
- [Output formats](#output-formats) — `-o table|json`
- [Verbose and debug](#verbose-and-debug) — see what the CLI is actually doing

---

## Auth

`aca` does not maintain its own credential store. Auth is delegated to the Azure CLI.

### Why customers care

You already have an Azure CLI session for everything else you do in Azure. `aca` reuses it — same identity, same MFA, same conditional-access policies. Nothing new to learn, nothing extra to manage.

### Commands

```bash
aca auth login    # delegates to `az login`
aca auth status   # shows current ARM + data-plane auth
```

`aca auth status` output:

```
✓ ARM authenticated via Azure CLI
✓ Data plane authenticated (https://dynamicsessions.io/.default)
```

### Switching subscriptions

`aca` reads the **active Azure CLI account** by default. Switch it with `az`:

```bash
az account set --subscription <SUB_ID>
```

Or override per-command:

```bash
aca sandbox list --subscription <SUB_ID>
```

Or set a default in CLI config (see [Config deep dive](#config-deep-dive)):

```bash
aca config set --subscription <SUB_ID>
```

### Managed identity (Azure-hosted)

When running inside Azure (App Service, Container Apps, VM, Functions), pass `--managed-identity`:

```bash
aca sandbox list --managed-identity system            # system-assigned
aca sandbox list --managed-identity <CLIENT_ID_UUID>  # user-assigned
```

Available on **every** command. Also settable via `ACA_SANDBOX_MANAGED_IDENTITY` env or `aca config sandbox set --managed-identity …`.

[↑ Back to top](#contents)

---

## Help commands

Every command, group, and sub-group responds to `--help`. The help text is the source of truth — examples, flags, env-var names, and defaults are all there.

### Why customers care

Customers don't read docs front-to-back. They tab into help. The `aca` help tree exposes every argument, the relevant env-var name, the default value, and (for top-level commands) ready-to-run examples — so you can self-serve every command without leaving the terminal.

### The three levels

```bash
aca --help                          # top-level: commands + global flags + quick start + scenarios
aca <group> --help                  # group: list of sub-commands
aca <group> <command> --help        # command: arguments, env vars, defaults, examples
```

### Top-level help highlights

`aca --help` lists the command surface:

```
Commands:
  auth          Log in and check authentication status
  config        Manage CLI configuration
  sandboxgroup  Manage sandbox groups, disks, volumes, secrets, roles, and regions
  sandbox       Create and manage sandboxes (exec, shell, files, ports, egress, snapshots)
  version       Show CLI version
  doctor        Check prerequisites, config, and RBAC (8 checks)
```

It also prints a **Quick start** block with copy-pasteable commands and a **Scenarios** table covering common workflows (first sandbox, run a script, interactive shell, egress lockdown, snapshot & restore, YAML spec, by-ID).

### Global flags appear on every command

Every command surfaces the same global flags (`--subscription`, `--resource-group`, `--sandbox-group`, `--output`, `--verbose`, `--debug`, `--managed-identity`, `--region`) along with the env-var name for each. Run `aca <anything> --help` to see them.

### Two-letter aliases

`aca <group> <command> -h` prints a summary; `--help` prints the long form with full descriptions and examples.

[↑ Back to top](#contents)

---

## Config deep dive

`aca` config lives at `~/.aca/config.json` and has two user-facing sections.

### Why customers care

Stop typing `--subscription … --resource-group … --sandbox-group …` on every command. Set once, work for the rest of the session — and have a precedence model that lets CI override anything via environment variables without editing files.

### Sections

| Section | What goes there |
|---|---|
| **Shared Defaults** | Subscription, resource group, region — used by every command that doesn't override them. |
| **Sandbox** | Sandbox-specific keys: sandbox group, auto-resume behavior, current sandbox, managed identity, audience, allowed regions, and per-section overrides for sub/RG/region. |

### See your current config

```bash
aca config show
```

Sample output (truncated):

```
Configuration:
  Shared Defaults:
    subscription     a59d7183-…
    resource_group   ai-apps-samples-rg
    region           westus2

  Sandbox:
    subscription     (inherited)
    resource_group   (inherited)
    region           westus2
    group            ai-apps-samples-group
    auto_resume      true
    current_sandbox  (not set)
    managed_identity (not set)
    audience         (not set)

Config file: C:\Users\<you>\.aca\config.json
```

`(inherited)` means the Sandbox section inherits from Shared Defaults for that key.

### Set Shared Defaults

```bash
aca config set \
  --subscription <SUB_ID> \
  --resource-group <RG> \
  --region westus2
```

Flags accepted by `aca config set`:

| Flag | Effect |
|---|---|
| `--subscription` | Default subscription for all commands. |
| `--resource-group` | Default resource group. |
| `--region` | Default data-plane region. |
| `--sandbox-group` | Default sandbox group name. |

### Set Sandbox-specific config

```bash
aca config sandbox set \
  --group ai-apps-samples-group \
  --auto-resume true \
  --sandbox <UUID>
```

Flags accepted by `aca config sandbox set`:

| Flag | Effect |
|---|---|
| `--subscription` / `-s` | Override Shared subscription for sandbox commands only. |
| `--resource-group` / `-g` | Override Shared resource group for sandbox commands only. |
| `--region` | Override Shared region for sandbox commands only. |
| `--group` | Default sandbox group name. |
| `--auto-resume true\|false` | Auto-resume a suspended sandbox before operations. |
| `--managed-identity system\|<CLIENT_ID>` | Use a managed identity for auth. |
| `--audience <URL>` | Override OAuth audience/scope (e.g. `https://dynamicsessions.io/.default`). |
| `--sandbox <UUID>` | "Current" sandbox ID — used when a command needs one but none is supplied. Pass `""` to clear. |
| `--add-region <REGION>` / `--remove-region <REGION>` | Add / remove a region from the allowed list (repeatable). |

### Precedence

For any setting, the CLI resolves in this order (highest wins):

1. **Command-line flag** (e.g. `--subscription <X>`)
2. **Environment variable** (e.g. `ACA_SUBSCRIPTION=<X>`)
3. **Sandbox-specific config** (set via `aca config sandbox set`)
4. **Shared Defaults config** (set via `aca config set`)

Each global flag's `--help` line shows its env-var name in brackets — e.g. `--subscription <SUBSCRIPTION> [env: ACA_SUBSCRIPTION=]`.

### Inspecting the file directly

```bash
cat ~/.aca/config.json
```

It's plain JSON; you can edit by hand or check it in (without secrets) for team-wide defaults.

[↑ Back to top](#contents)

---

## `doctor`

`aca doctor` runs 8 prerequisite/config/RBAC checks. If anything is wrong, it tells you what.

### Why customers care

It's the single fastest path from *"nothing works"* to *"fixed"*. Each failed check maps to a specific action. Run it on a fresh machine, after switching subscriptions, or any time something stops working.

### Run it

```bash
aca doctor
```

Sample output (all green):

```
✓ Azure CLI found
✓ Azure CLI logged in
✓ Subscription: a59d7183-… (config)
✓ Resource group: ai-apps-samples-rg (config)
✓ Sandbox group: ai-apps-samples-group (config: sandbox)
✓ Region: westus2 (config: sandbox)
✓ Sandbox group 'ai-apps-samples-group' exists in Azure
✓ Container Apps SandboxGroup Data Owner role assigned

aca 1.0.0-beta.1 — all checks passed
```

### What each check verifies, and how to fix it

| Check | Means | Fix |
|---|---|---|
| Azure CLI found | `az` is on PATH | Install Azure CLI |
| Azure CLI logged in | `az account show` succeeds | `az login` |
| Subscription | Resolves a default subscription | `aca config set --subscription <ID>` or `az account set` |
| Resource group | Resolves a default RG | `aca config set --resource-group <RG>` |
| Sandbox group | Resolves a default sandbox group | `aca config sandbox set --group <NAME>` |
| Region | Resolves a default region | `aca config sandbox set --region <REGION>` |
| Sandbox group exists | The group resource is found in Azure | `aca sandboxgroup create --name <NAME> --location <REGION> --set-config` |
| Data Owner role | Caller has `Container Apps SandboxGroup Data Owner` on the group | `aca sandboxgroup role create --role "Container Apps SandboxGroup Data Owner" --principal-id $(az ad signed-in-user show --query id -o tsv)` |

Lines also show **where the value came from** — `(config)`, `(config: sandbox)`, `(env)`, `(flag)` — which is gold when debugging precedence.

[↑ Back to top](#contents)

---

## YAML spec workflow

Define a sandbox in YAML, validate, then apply. CLI-only — the SDK has no equivalent.

### Why customers care

This is the infra-as-code story. Check sandbox specs into git, code-review them, validate in CI before apply, and get editor autocomplete from the published JSON Schema. It's the reason a team would standardize on the CLI for **provisioning** even when they use the SDK at runtime.

### The four commands

| Command | Does |
|---|---|
| `aca sandbox init` | Print a starter spec to stdout. |
| `aca sandbox schema` | Print the JSON Schema for sandbox specs (for editor integration). |
| `aca sandbox validate --file <FILE>` | Validate a spec file without creating anything. |
| `aca sandbox apply --file <FILE> [--no-wait]` | Create the sandbox from the spec. |

### End-to-end

```bash
aca sandbox init > sandbox.yaml
```

Generates:

```yaml
# ACA Sandbox manifest
# Apply with: aca sandbox apply --file sandbox.yaml

disk: ubuntu
resources:
  cpu: 1000m
  memory: 2048Mi
lifecycle:
  autoSuspendPolicy:
    enabled: true
    interval: 300
    mode: Memory
egressPolicy:
  defaultAction: Deny
```

Edit it (set labels, change `cpu`/`memory`, tighten egress), then:

```bash
aca sandbox validate --file sandbox.yaml
aca sandbox apply --file sandbox.yaml
```

Add `--no-wait` to return as soon as the create is accepted (don't wait for Running).

### Editor integration via `schema`

```bash
aca sandbox schema > sandbox.schema.json
```

Point your editor at it (`yaml.schemas` in VS Code, `:set yaml-language-server` in Neovim) to get autocomplete and inline validation while editing specs.

### Validate in CI

```bash
aca sandbox validate --file sandbox.yaml
```

Exit code is non-zero on validation failure — drop this into a pre-merge check to catch spec drift before it hits Azure.

[↑ Back to top](#contents)

---

## Selectors

Every command that operates on a sandbox/disk/snapshot/volume accepts either a UUID or a label selector.

### Why customers care

UUIDs are unmemorable and ephemeral. Selectors let you script against labels you control. `-l "env=ci,role=worker"` works the same in your dev shell, your cleanup cron, your dashboard, and your alerting — none of which need to track IDs anywhere.

### The two forms

```bash
# By ID (UUID)
aca sandbox exec --id 0d9b1c4e-… -c "echo hello"

# By selector — labels you set at create-time
aca sandbox exec -l "name=dev" -c "echo hello"
```

### Selector grammar

- `key=value` — match exactly
- `key1=v1,key2=v2` — AND (all pairs must match)
- Spaces around `=` and `,` are **not** allowed
- For `get` and `delete`, the CLI matches the **first** sandbox satisfying the selector

### Set labels at create-time

```bash
aca sandbox create --disk ubuntu \
  --label env=ci \
  --label role=worker \
  --label owner=alice
```

The flag is `--label key=value`, repeatable — one label per flag occurrence.

Then operate on it without ever quoting the UUID:

```bash
aca sandbox exec -l "env=ci,role=worker" -c "./run.sh"
aca sandbox stop -l "env=ci,role=worker"
aca sandbox delete -l "env=ci,role=worker"
```

### When to pick which

| Use | Form |
|---|---|
| Long-lived dev sandbox | Selector — friendlier in shell history |
| Output of a previous command | UUID — already in your shell variable |
| Batch operation across many | `list -o json` + `jq` + UUID loop |
| Cleanup by ownership tag | Selector — labels are your contract |

[↑ Back to top](#contents)

---

## Output formats

Every command supports `-o table|json`. Default is `table`.

### Why customers care

Table for humans, JSON for pipelines. This is what makes `aca` scriptable — every command becomes a building block for shell pipelines, CI, and dashboards without screen-scraping.

### Two modes

```bash
aca sandbox list                 # table (default)
aca sandbox list -o json         # JSON array
```

### Piping JSON to `jq`

Pull just the IDs:

```bash
aca sandbox list -o json | jq -r '.[].id'
```

Find Running sandboxes labeled `env=ci`:

```bash
aca sandbox list -o json | jq -r '.[] | select(.state=="Running" and .labels.env=="ci") | .id'
```

Bulk delete by tag:

```bash
aca sandbox list -o json | \
  jq -r '.[] | select(.labels.env=="ci") | .id' | \
  xargs -I{} aca sandbox delete --id {}
```

### Diffing JSON snapshots

For human-readable diffs between two snapshots of the same resource, dump JSON and use `jq` to pretty-print consistently:

```bash
aca sandbox get --id $ID -o json | jq -S . > before.json
# ... do something ...
aca sandbox get --id $ID -o json | jq -S . > after.json
diff before.json after.json
```

### Table for humans, always defaultable

If you forget `-o`, you get a table — which is exactly what you want in interactive shells. The flag is global so it works on every command.

[↑ Back to top](#contents)

---

## Verbose and debug

When a command does the wrong thing, `--verbose` shows exactly what.

### Why customers care

Cuts support cycles dramatically. `--verbose` tells you (1) which subscription/RG/region the CLI *actually* resolved from your flags/env/config and (2) the full HTTP request/response — so you can see whether the bug is yours or ours.

### `--verbose`

```bash
aca sandbox list --verbose
```

Outputs:

- The **resolved config** dump (where each value came from: flag, env, sandbox-config, shared-config)
- HTTP **request line**, headers, and status for each call
- Response headers (bodies elided)

### `--debug`

```bash
aca sandbox list --debug
```

Includes everything `--verbose` does **plus** transport-level details (TLS, retries, raw response bodies).

> ⚠️ **`--debug` may log sensitive data** (secret values, tokens in error bodies). Don't share the output of a `--debug` run without reviewing it first. The CLI warns about this in the flag description.

### Use them together with redirects

```bash
aca sandbox apply --file sandbox.yaml --verbose 2> aca.log
```

Stdout stays clean for piping; verbose / debug traces go to stderr so you can capture them separately.

[↑ Back to top](#contents)
