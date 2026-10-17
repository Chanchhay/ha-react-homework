import express from 'express';
import { randomUUID } from 'node:crypto';
import { hostname } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const app = express();
const port = Number(process.env.PORT || 3000);
const serverId = process.env.SERVER_ID || 'UNCONFIGURED';
const serverIp = process.env.WEB_IP || 'NOT_CONFIGURED';
const dist = join(dirname(fileURLToPath(import.meta.url)), 'dist');

// HAProxy checks /health to decide whether this backend can receive traffic.
app.get('/health', (_req, res) => {
  res.set('Cache-Control', 'no-store');
  res.status(200).type('text/plain').send('OK');
});

// Identity is generated at RUNTIME, not baked into the static React build.
app.get('/api/trace', (req, res) => {
  const record = {
    requestId: randomUUID(),
    backend: serverId,
    backendIp: serverIp,
    machineHostname: hostname(),
    serverTime: new Date().toISOString(),
    appUptimeSeconds: Math.floor(process.uptime()),
    // This field confirms a healthy response from the current app process.
    health: 'OK',
  };
  res.set('Cache-Control', 'no-store');
  res.json(record);
  console.log(JSON.stringify({ event: 'trace', ...record }));
});

// The built React application is identical on both web servers.
app.use(express.static(dist, { index: 'index.html' }));

// Allow client-side React routes while keeping unknown API endpoints as 404.
app.use((req, res, next) => {
  if (req.method !== 'GET' || req.path.startsWith('/api/')) {
    return res.status(404).json({ error: 'Not found' });
  }
  res.sendFile(join(dist, 'index.html'), (error) => {
    if (error) next(error);
  });
});

app.listen(port, '0.0.0.0', () => {
  console.log(`HTTP server ${serverId} (${serverIp}) listening on :${port}`);
});
