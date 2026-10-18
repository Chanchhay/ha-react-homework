## Usage and execution context

The shared `/vagrant` directory is provided by Vagrant (inside the VMs). It is the host directory containing `Vagrantfile`, which lets a VM access your local `react-app` and `scripts`.

**From your host (in the project directory)**:

```bash
# If you use Linux/macOS/WSL/Git Bash and have npm + Vagrant on PATH:
bash scripts/deploy-react.sh

# Check both web backends:
bash scripts/check-health.sh

# Check both backends, both LBs and VIP:
bash scripts/check-health.sh --all
```

**From your host, invoke VM-side commands**:

```bash
vagrant ssh web-01 -c 'sudo bash /vagrant/scripts/setup-web.sh'
vagrant ssh web-02 -c 'sudo bash /vagrant/scripts/setup-web.sh'

vagrant ssh web-01 -c 'sudo bash /vagrant/scripts/service-manager.sh restart'
vagrant ssh web-01 -c 'bash /vagrant/scripts/server-report.sh'
vagrant ssh lb-01 -c 'bash /vagrant/scripts/server-report.sh'
```

### What the deploy script does

1. Runs `npm ci` and `npm run build` on **your host** so both backends use the _same production build_.
2. Uses Vagrant SSH to run itself in `--install` mode on WEB-01, then WEB-02.
3. On each web VM, stops `react-app` briefly, copies the built `dist`, `server.mjs`, package manifests, installs locked production dependencies, sets `SERVER_ID`/`WEB_IP` in the supplied service file and restarts systemd.
4. Verifies `/health` before moving to the next VM.

**Assumptions:**

- Project folder contains `Vagrantfile`, `react-app`, `scripts` at the same level.
- `react-app/package-lock.json` exists (create with `npm install` on your host if missing).
- Host has a recent Node.js compatible with the Vite project, npm, and Vagrant.
- Vagrant shares your project directory with each VM as `/vagrant`.
- On each web VM, Node.js 22 and the `reactapp` service account have been set up with `setup-web.sh` (or manually), and `/usr/bin/node` is valid for the service file.
- You ran the earlier manual deployment with `react-app/deploy/react-app.service`; if you customize that unit, review the template before using this script.

The script **does not** implement rollback or truly zero-downtime deployment. The other backend should continue serving traffic while one server is updated, but current requests can briefly fail. Production rolling releases should drain connections and preserve rollback artifacts first.

### Error handling

Scripts exit nonzero on failed checks/actions, validate arguments, use variables and functions, and don't contain passwords. `check-health.sh` returns `0` when all requested endpoints are healthy and `1` if any are unhealthy. Most usage errors return `64`.

### Security note

`setup-web.sh` downloads the NodeSource Node.js 22 repository configuration. Review remote setup scripts before running them as root on trusted production machines. This is a private development lab, not a hardened production deployment.
