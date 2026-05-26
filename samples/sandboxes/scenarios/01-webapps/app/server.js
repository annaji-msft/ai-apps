// Tiny Node HTTP server used by both webapp variants in scenarios/01-webapps.
// No external dependencies — uses the built-in `http` and `os` modules so the
// sandbox doesn't need `npm install` before starting.

const http = require('http');
const os = require('os');

const PORT = parseInt(process.env.PORT || '8080', 10);

function json(res, status, body) {
  res.writeHead(status, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify(body, null, 2) + '\n');
}

const routes = {
  '/': () => ({
    message: 'Hello from sandbox',
    hostname: os.hostname(),
    uptime: Math.round(process.uptime()),
  }),
  '/healthz': () => ({ status: 'ok' }),
  '/api/info': () => ({
    node: process.version,
    platform: process.platform,
  }),
};

http.createServer((req, res) => {
  const path = req.url.split('?')[0];
  const handler = routes[path];
  if (handler) {
    json(res, 200, handler());
  } else {
    json(res, 404, { error: 'not found', path });
  }
}).listen(PORT, '0.0.0.0', () => {
  console.log(`Server listening on :${PORT}`);
});
