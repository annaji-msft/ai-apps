// Tiny Node HTTP server used by both webapp variants in scenarios/01-webapps.
// No external dependencies — uses the built-in `http` and `os` modules so the
// sandbox doesn't need `npm install` before starting.
//
//   GET /            -> HTML landing page ("Hello from a sandbox")
//   GET /healthz     -> { status: "ok" }
//   GET /api/hello   -> { message, hostname, uptime, pid }
//   GET /api/info    -> { node, platform, arch, memory }

const http = require('http');
const os = require('os');

const PORT = parseInt(process.env.PORT || '8080', 10);
const STARTED_AT = new Date();

function json(res, status, body) {
  res.writeHead(status, { 'Content-Type': 'application/json; charset=utf-8' });
  res.end(JSON.stringify(body, null, 2) + '\n');
}

function html(res, status, body) {
  res.writeHead(status, { 'Content-Type': 'text/html; charset=utf-8' });
  res.end(body);
}

function hello() {
  return {
    message: 'Hello from sandbox',
    hostname: os.hostname(),
    uptime: Math.round(process.uptime()),
    pid: process.pid,
  };
}

function info() {
  return {
    node: process.version,
    platform: process.platform,
    arch: process.arch,
    cpus: os.cpus().length,
    memoryMB: Math.round(os.totalmem() / 1024 / 1024),
    startedAt: STARTED_AT.toISOString(),
  };
}

function page() {
  const h = hello();
  const i = info();
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Hello from an Azure Container Apps sandbox</title>
<style>
  :root {
    --bg: #0b1020;
    --bg-2: #11183a;
    --fg: #e7ecff;
    --muted: #9aa6d6;
    --accent: #6ea8ff;
    --accent-2: #b388ff;
    --card: rgba(255,255,255,0.04);
    --border: rgba(255,255,255,0.08);
  }
  * { box-sizing: border-box; }
  html, body { margin: 0; padding: 0; }
  body {
    font: 16px/1.55 -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
    color: var(--fg);
    background: radial-gradient(1200px 600px at 10% -10%, #1d2761 0%, transparent 60%),
                radial-gradient(900px 500px at 110% 110%, #3b1a66 0%, transparent 55%),
                linear-gradient(180deg, var(--bg) 0%, var(--bg-2) 100%);
    min-height: 100vh;
  }
  .wrap { max-width: 920px; margin: 0 auto; padding: 56px 24px 80px; }
  header { display: flex; align-items: center; gap: 14px; margin-bottom: 32px; }
  .logo {
    width: 44px; height: 44px; border-radius: 12px;
    background: linear-gradient(135deg, var(--accent), var(--accent-2));
    display: grid; place-items: center; font-weight: 800; color: #0b1020;
  }
  .badge {
    margin-left: auto;
    font-size: 12px; letter-spacing: .08em; text-transform: uppercase;
    color: var(--muted);
    border: 1px solid var(--border); border-radius: 999px;
    padding: 6px 12px;
  }
  h1 {
    font-size: clamp(28px, 4.5vw, 44px);
    line-height: 1.1; margin: 0 0 8px;
    background: linear-gradient(90deg, var(--accent), var(--accent-2));
    -webkit-background-clip: text; background-clip: text; color: transparent;
  }
  .lede { color: var(--muted); font-size: 18px; margin: 0 0 28px; max-width: 70ch; }
  .grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(220px, 1fr)); gap: 14px; margin: 18px 0 36px; }
  .card {
    background: var(--card); border: 1px solid var(--border); border-radius: 14px;
    padding: 16px 18px;
  }
  .card .k { font-size: 12px; letter-spacing: .08em; text-transform: uppercase; color: var(--muted); margin-bottom: 6px; }
  .card .v { font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace; font-size: 15px; word-break: break-all; }
  .row { display: grid; grid-template-columns: 1fr 1fr; gap: 14px; margin: 18px 0; }
  @media (max-width: 720px) { .row { grid-template-columns: 1fr; } }
  .panel {
    background: var(--card); border: 1px solid var(--border); border-radius: 16px;
    padding: 22px;
  }
  .panel h2 { margin: 0 0 10px; font-size: 18px; }
  .panel p, .panel li { color: var(--muted); margin: 6px 0; }
  code, pre {
    font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
    font-size: 13px;
  }
  pre {
    background: rgba(0,0,0,0.35); border: 1px solid var(--border); border-radius: 10px;
    padding: 14px 16px; overflow-x: auto; color: var(--fg);
  }
  a { color: var(--accent); }
  .endpoints { display: grid; gap: 8px; }
  .ep {
    display: flex; align-items: center; gap: 12px;
    padding: 10px 12px; border: 1px solid var(--border); border-radius: 10px;
    background: rgba(0,0,0,0.2);
  }
  .ep .m { font-weight: 700; color: var(--accent); width: 44px; }
  .ep a { color: var(--fg); text-decoration: none; font-family: ui-monospace, monospace; }
  .ep a:hover { color: var(--accent); }
  .ep .d { margin-left: auto; color: var(--muted); font-size: 13px; }
  .pulse { display: inline-block; width: 8px; height: 8px; border-radius: 50%;
    background: #4ade80; box-shadow: 0 0 0 0 rgba(74,222,128,0.7);
    animation: pulse 1.8s infinite; vertical-align: middle; margin-right: 8px; }
  @keyframes pulse { 0% { box-shadow: 0 0 0 0 rgba(74,222,128,0.6); } 70% { box-shadow: 0 0 0 12px rgba(74,222,128,0); } 100% { box-shadow: 0 0 0 0 rgba(74,222,128,0); } }
  footer { margin-top: 36px; color: var(--muted); font-size: 13px; text-align: center; }
  footer a { color: var(--muted); }
</style>
</head>
<body>
<div class="wrap">
  <header>
    <div class="logo">A</div>
    <div>
      <div style="font-weight:700">Azure Container Apps</div>
      <div style="color:var(--muted); font-size:13px">Sandbox demo</div>
    </div>
    <div class="badge"><span class="pulse"></span>live</div>
  </header>

  <h1>Hello from a sandbox 👋</h1>
  <p class="lede">
    This page is being served by a tiny Node.js process running inside an
    Azure Container Apps <strong>sandbox</strong> — an isolated, ephemeral
    micro-VM you can boot in seconds, expose ports from, push files into,
    and tear down when you're done. No cluster, no Dockerfile, no YAML.
  </p>

  <div class="grid">
    <div class="card"><div class="k">message</div><div class="v">${h.message}</div></div>
    <div class="card"><div class="k">hostname</div><div class="v">${h.hostname}</div></div>
    <div class="card"><div class="k">uptime (s)</div><div class="v" id="uptime">${h.uptime}</div></div>
    <div class="card"><div class="k">pid</div><div class="v">${h.pid}</div></div>
    <div class="card"><div class="k">node</div><div class="v">${i.node}</div></div>
    <div class="card"><div class="k">platform / arch</div><div class="v">${i.platform} / ${i.arch}</div></div>
    <div class="card"><div class="k">cpus</div><div class="v">${i.cpus}</div></div>
    <div class="card"><div class="k">memory</div><div class="v">${i.memoryMB} MB</div></div>
  </div>

  <div class="row">
    <div class="panel">
      <h2>What is a sandbox?</h2>
      <p>
        A sandbox is a managed, single-tenant micro-VM with a public-disk root
        filesystem. It boots in seconds, runs anything you can run in Linux,
        and gives you simple primitives: <code>exec</code>, <code>write_file</code>,
        <code>add_port</code>, <code>add_volume_mount</code>, and friends.
      </p>
      <p>
        It's the right tool when you want code execution that's
        <em>fast</em>, <em>isolated</em>, and <em>disposable</em> — agent
        tool-use, code interpreters, per-PR preview envs, untrusted user code.
      </p>
    </div>
    <div class="panel">
      <h2>How this page got here</h2>
      <pre>aca sandbox create --disk node-22
aca sandbox fs write --path /app/server.js --file server.js
aca sandbox exec   -c "node /app/server.js &amp;"
aca sandbox port add --port 8080 --anonymous
# (or --email you@contoso.com for Entra-gated access)</pre>
      <p>
        Full source:
        <a href="https://github.com/annaji-msft/aca/tree/main/samples/sandboxes/scenarios/01-webapps" target="_blank" rel="noopener">samples/sandboxes/scenarios/01-webapps</a>.
      </p>
    </div>
  </div>

  <div class="panel">
    <h2>Endpoints on this sandbox</h2>
    <div class="endpoints">
      <div class="ep"><span class="m">GET</span><a href="/">/</a><span class="d">this page</span></div>
      <div class="ep"><span class="m">GET</span><a href="/healthz">/healthz</a><span class="d">liveness probe (JSON)</span></div>
      <div class="ep"><span class="m">GET</span><a href="/api/hello">/api/hello</a><span class="d">message + uptime (JSON)</span></div>
      <div class="ep"><span class="m">GET</span><a href="/api/info">/api/info</a><span class="d">runtime + host info (JSON)</span></div>
    </div>
  </div>

  <footer>
    Served from <code>${h.hostname}</code> · uptime <code>${h.uptime}s</code> · started <code>${STARTED_AT.toISOString()}</code>
  </footer>
</div>
<script>
  // Tick the uptime counter so the page feels alive.
  (function() {
    var el = document.getElementById('uptime');
    var n = parseInt(el.textContent, 10) || 0;
    setInterval(function() { el.textContent = (++n).toString(); }, 1000);
  })();
</script>
</body>
</html>`;
}

const routes = {
  '/':           { handler: (res) => html(res, 200, page()) },
  '/healthz':    { handler: (res) => json(res, 200, { status: 'ok' }) },
  '/api/hello':  { handler: (res) => json(res, 200, hello()) },
  '/api/info':   { handler: (res) => json(res, 200, info()) },
};

http.createServer((req, res) => {
  const path = req.url.split('?')[0];
  const route = routes[path];
  if (route) {
    route.handler(res);
  } else {
    json(res, 404, { error: 'not found', path });
  }
}).listen(PORT, '0.0.0.0', () => {
  console.log(`Server listening on :${PORT}`);
});
