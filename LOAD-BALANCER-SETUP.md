# Automating HAProxy and Keepalived (Task 5 extension)

This bundle extends the earlier five homework scripts with a sixth optional script, `scripts/setup-lb.sh`, to configure both load balancers. It assumes you have four Vagrant VMs (lb-01, lb-02, web-01, web-02), React accessible on WEB-01/WEB-02 at port 3000, and their `/health` endpoints returning status 200.

## Files

- `scripts/setup-lb.sh`: VM-side install/configure script, detects lb-01 versus lb-02 by `hostname -s`
- `haproxy/lb-01.cfg`, `haproxy/lb-02.cfg`: complete HAProxy files with frontends/backends
- `keepalived/lb01.conf`, `keepalived/lb02.conf`: unicast VRRP configs for floating VIP `192.168.56.100`, priorities 150 and 100 respectively

The Keepalived configs use `eth1` because your VM output showed that your `192.168.56.x` addresses use `eth1`. If another image uses a different interface name, update `interface` and `dev` in both Keepalived files and pass `NETWORK_IF=...` to the script.

## Install

Copy `scripts/`, `haproxy/` and `keepalived/` into the host project directory alongside your Vagrantfile. Vagrant shares this directory inside each VM at `/vagrant`.

**Review the included full configuration files before using.** This script replaces the system config files, so it may overwrite edits you made manually. It saves previous versions under `/var/backups/ha-react/<timestamp>-<hostname>/` before applying changes.

To configure the standby first, from your host run:

```bash
vagrant ssh lb-02 -c 'sudo bash /vagrant/scripts/setup-lb.sh'
vagrant ssh lb-01 -c 'sudo bash /vagrant/scripts/setup-lb.sh'
```

The script installs packages using APT, validates both configs, backs up existing configs, installs the correct files for that hostname, enables HAProxy and Keepalived, restarts/reloads services, and verifies that a local HTTP health check works. A Keepalived restart on the active LB can briefly move the VIP.

## Verify

```bash
# On your host:
curl -i http://192.168.56.100/api/trace

# VIP should appear on only one LB:
vagrant ssh lb-01 -c 'ip -4 addr show eth1'
vagrant ssh lb-02 -c 'ip -4 addr show eth1'

# Test failover:
vagrant ssh lb-01 -c 'sudo systemctl stop haproxy'
curl -i http://192.168.56.100/api/trace
vagrant ssh lb-01 -c 'sudo systemctl start haproxy'
```

Expected: normal VIP ownership on LB-01, VIP transfer to LB-02 after HAProxy stops, return to LB-01 after recovery under the default preemptive policy.

## Restore a previous configuration

If your custom settings were overwritten, locate the backup directory printed by the script. On the affected LB, copy its saved files back into `/etc/haproxy/haproxy.cfg` and `/etc/keepalived/keepalived.conf`, validate them, then restart/reload the corresponding services. Keep the original config files in Git when they contain project-specific settings you want to preserve.

## Note on advanced environments

This is a development-lab provisioner, not a production rolling-change controller. It does not drain traffic or guarantee atomic rollback if a service restart fails. VRRP (IP protocol 112) must be allowed between both VMs. If both load balancers acquire the VIP, stop and troubleshoot peer connectivity.
