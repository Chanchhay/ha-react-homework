# HA Infrastructure Monitor

A real-time React dashboard for the Vagrant + HAProxy + Keepalived homework.

## How it works

1. The browser makes a fresh `GET /api/trace` every 3 seconds.
2. The active HAProxy adds `X-Load-Balancer: LB-01` or `LB-02` to the HTTP response.
3. The Node.js HTTP server returns the backend identity (`SERVER_ID`), timestamp, hostname, process uptime and a request ID.
4. React combines the response header and JSON body to show the **real path of this API request**.
5. When the site is opened directly on `http://192.168.56.20:3000`, no HAProxy header exists, so it shows `DIRECT`.

The dashboard **does not** claim to know the state of all servers just because its last request succeeded. True backend pool status and VIP ownership require a separately secured monitoring endpoint.

## Requirements

- Node.js 20.19+ or 22.12+ (Node.js 22 LTS is suitable)
- npm
- Install dependencies with `npm install`

## Try it without HAProxy

```bash
npm install
npm run build
SERVER_ID=WEB-01 WEB_IP=192.168.56.20 npm start
```

Open http://localhost:3000. It should show `DIRECT` and `WEB-01`. The static `dist/` build is identical on both VMs.

For frontend development (two terminals):

```bash
# First terminal, start the API server. A dist/ build is not needed for API calls.
SERVER_ID=WEB-01 WEB_IP=192.168.56.20 npm start

# Second terminal, start Vite; /api is proxied to :3000.
npm run dev
```

## Deploy to WEB-01 and WEB-02

For each VM:

1. Install Node.js 22.
2. Create the dedicated non-root Linux user `reactapp`.
3. Copy this project to `/opt/react-app`; run `npm ci --omit=dev` if you have a lockfile, otherwise `npm install --omit=dev`. Ensure the `dist/` directory was built and copied over, or build on the VM with dev dependencies installed.
4. Set correct `SERVER_ID` and `WEB_IP` values in the systemd unit found at `deploy/react-app.service`. For WEB-02, use `WEB-02` and `192.168.56.21`.
5. If Node is installed in a different location than `/usr/bin/node`, update `ExecStart` accordingly (`command -v node`).
6. Enable the service with:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now react-app
sudo systemctl status react-app
```

Test:

```bash
curl -i http://192.168.56.20:3000/health
curl -i http://192.168.56.20:3000/api/trace
curl -i http://192.168.56.21:3000/api/trace
```

## Configure HAProxy

Merge the corresponding config snippet from `deploy/` into the correct load balancer's `/etc/haproxy/haproxy.cfg` (don't erase the existing `global` and `defaults`). Do **not** include the other load balancer's snippet on the same VM.

Before restarting, validate:

```bash
sudo haproxy -c -f /etc/haproxy/haproxy.cfg
sudo systemctl enable --now haproxy
sudo systemctl reload haproxy
```

Check the **response header** and the **JSON response body**:

```bash
curl -i http://192.168.56.10/api/trace
curl -i http://192.168.56.11/api/trace
```

After Keepalived is configured, open `http://192.168.56.100` in your browser to track failover. Stop HAProxy on LB-01 to test takeover and observe the changing load balancer on fresh API requests.

## Limitations and diagnostic integrity

- The initial HTML load and later `/api/trace` call are different HTTP requests. This UI reports only the latter's path.
- Each load balancer runs its own round-robin algorithm; a VIP failover changes the instance making backend routing decisions.
- Sample percentages are from the current browser's last 60 requests; not global load balancer metrics.
- During takeover, some fetches may fail briefly; this is not proof that both web servers are down.
- The load balancer label is trusted only on responses forwarded through a correctly configured HAProxy. A direct request has no response header. Do not expose diagnostic/management features as-is on a public production service.
- The frontend does not attempt to stop services or grant SSH privileges; failure tests are carried out via trusted terminal access.
