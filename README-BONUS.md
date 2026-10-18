# Two-tier bootstrap: Base and Bonus

This is an **overlay** for the existing ha-react-homework project. Copy its `bonus/` directory to the project root and **merge** (or replace, if unchanged) the included Justfile. Keep `scripts/`, `haproxy/`, `keepalived/`, and the base application as they are.

## Reproducible lifecycle

```bash
just bootstrap          # Four VMs + basic React + HAProxy + Keepalived
just health-all         # Verify baseline
just bootstrap-bonus    # Upgrade running environment: stats, runtime API, versioned releases
just bonus-status       # Verify both web releases and both HAProxy management interfaces
just stats              # Show authenticated stats URLs
just stats-password lb-01   # Retrieve generated password (username: viewer)
just stats-password lb-02
just releases           # Inspect current and available releases
just deploy-github main # Fetch GitHub origin/main and roll out a new release
just rollback baseline  # Return both web servers to pre-bonus baseline
just destroy DESTROY    # Delete VMs; code remains in your repository
just bootstrap          # Pure base again
just bootstrap-bonus    # Recreate bonus features without manual config
```

### Prerequisites

- Your previous base bundle including `scripts/setup-web.sh`, `scripts/setup-lb.sh`, `scripts/deploy-react.sh`, and the HAProxy base configurations must be present in your repository.
- `just bootstrap` must complete successfully before `just bootstrap-bonus`.
- This uses Vagrant shared folders (`/vagrant`), four VM names from your homework, and **eth1** as the existing Keepalived interface.
- `just deploy-github` requires an `origin` remote, an accessible branch, and `react-app/package-lock.json` committed to Git. Authentication is handled by the host's configured Git credentials; never embed tokens in scripts.
- Use a Bash-capable host shell with Vagrant, Node.js, npm, Git, Just, and tar available.
- Protected stats use a generated, per-VM password stored as root-only `/etc/ha-react/monitoring-password`. Username: `viewer`. The lab page is HTTP on the private host-only network: do not expose it to the internet.

### Separation guarantees and caveats

- `just bootstrap` never executes bonus scripts or creates bonus releases. The original base services remain unchanged.
- `just bootstrap-bonus` requires a healthy base. It enables HAProxy's runtime API and local authenticated stats listener; copies the running baseline to `/opt/react-app/releases/baseline`; updates systemd to run via `/opt/react-app/current` and rolls the migration through one backend at a time.
- Re-running `just bootstrap-bonus` on an already healthy bonus environment is designed to be safe; it does **not** fetch GitHub unless you request `just deploy-github`.
- Only use `just deploy-github`, `just deploy-release`, and `just rollback` to update bonus-mode applications. **Do not use original `just deploy`** after bonus mode: it overwrites the base path directly, not release directories.
- Destroying VMs removes releases, snapshots, logs, runtime credentials, and their disks. The tracked project and Justfile stay on the host. `.artifacts/` build cache also remains on host until cleaned manually.
- An HAProxy session drain, a successful `curl /health`, and staggered systemd restarts reduce interruptions, but **zero downtime is a test outcome, not an unconditional guarantee**. Test with continuous traffic through the VIP. Long-lived and persistent sessions need extra handling.
- If a rollout fails, VM-side activation restores the previous release on the affected backend when possible. A release already installed on WEB-01 may remain there if WEB-02 fails; use `just rollback <release-id>` to restore both to the same version. If backend recovery fails, it is deliberately left drained for troubleshooting.
- This bundle assumes a controlled, disposable VirtualBox lab. It is not a production secrets or orchestration stack.

## Architecture

Base uses `/opt/react-app/{dist,server.mjs,node_modules}`.

Bonus keeps that baseline intact and introduces:

```
/opt/react-app/
  dist/           # original baseline files preserved
  server.mjs      # original baseline preserved
  releases/
    baseline/
    a1b2c3d4e5f6/
  current -> releases/a1b2c3d4e5f6
```

On the HAProxy VMs, the bonus adds a root-only Runtime API Unix socket `/run/haproxy/admin.sock` and authenticated `/haproxy-stats` on port `8404` of each VM's static private IP. It does not change the Keepalived configuration or VIP address.

## Verifying rolling availability

Keep this request loop running in **one terminal** while deploying in another:

```bash
while true; do
  curl -fsS --max-time 3 -o /dev/null http://192.168.56.100/health || echo "FAILED $(date -Is)"
  sleep 0.2
done
```

Run `just deploy-github main` in the second terminal. An uninterrupted test is evidence for the bonus challenge, but it does not prove availability for every client connection or long-lived session.

For a safer first test, run `just bootstrap-bonus`, followed by `just bonus-status` and `just rollback baseline` before attempting a new GitHub release. The rollback command is safe when both nodes are already on `baseline`: it confirms the existing healthy release.
