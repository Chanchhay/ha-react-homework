# High Availability React Homework - command shortcuts
# Place this file beside Vagrantfile and run commands from your host computer.
# Requires: just, Vagrant, VirtualBox, Bash, curl, and Node.js/npm for deployments.

set shell := ["bash", "-uc"]
set positional-arguments

# List all available commands.
@default:
    just --list

# -------- Virtual machine lifecycle --------

# Check the status of all four virtual machines.
@status:
    vagrant status

# Start all VMs (first run also provisions base packages).
@up:
    vagrant up --provider=virtualbox

# Shut down all VMs without deleting them.
@down:
    vagrant halt

# Restart one VM or all VMs: just reload [vm|all].
@reload vm="all":
    if [[ "$1" == all ]]; then vagrant reload; else vagrant reload "$1"; fi

# Re-run Vagrant provisioning for one VM or all: just provision [vm|all].
@provision vm="all":
    if [[ "$1" == all ]]; then vagrant provision; else vagrant provision "$1"; fi

# SSH into a VM, e.g. just ssh lb-01.
@ssh vm:
    vagrant ssh "$1"

# Validate the Vagrantfile.
@validate:
    vagrant validate

# -------- Installation and deployment --------

# Prepare Node.js, reactapp user, and directories on both web servers.
@setup-web:
    vagrant ssh web-01 -c 'sudo bash /vagrant/scripts/setup-web.sh'
    vagrant ssh web-02 -c 'sudo bash /vagrant/scripts/setup-web.sh'

# Apply HAProxy + Keepalived configs, standby first. May cause VIP failover.
@setup-lb:
    vagrant ssh lb-02 -c 'sudo bash /vagrant/scripts/setup-lb.sh'
    vagrant ssh lb-01 -c 'sudo bash /vagrant/scripts/setup-lb.sh'

# Build the React app locally without deploying.
@build:
    cd react-app && npm ci && npm run build

# Build once on host, install on both web servers, and restart systemd.
@deploy:
    bash scripts/deploy-react.sh

# Full setup: create VMs, prepare web servers, deploy, and configure load balancers.
# WARNING: reapplies LB configs and can temporarily move the VIP.
@bootstrap:
    just up
    just setup-web
    just deploy
    just setup-lb
    just health-all

# -------- Health, monitoring, and diagnostics --------

# Check WEB-01 and WEB-02 health.
@health:
    bash scripts/check-health.sh

# Check both web servers, both load balancers, and the VIP.
@health-all:
    bash scripts/check-health.sh --all

# Show which LB and backend answered a request through the VIP.
@trace:
    curl --fail --silent --show-error --include http://192.168.56.100/api/trace

# Show the private-interface addresses and VIP owner on both LBs.
@vip:
    for vm in lb-01 lb-02; do echo "=== $vm ==="; vagrant ssh "$vm" -c 'ip -4 addr show dev eth1' || exit; done

# Check installed HAProxy and Keepalived configs on both LBs.
@validate-lb:
    for vm in lb-01 lb-02; do echo "=== $vm ==="; vagrant ssh "$vm" -c 'sudo haproxy -c -f /etc/haproxy/haproxy.cfg && sudo keepalived --config-test -f /etc/keepalived/keepalived.conf' || exit; done

# Report CPU, RAM, disk, IPs, and uptime: just report [vm].
@report vm="web-01":
    case "$1" in lb-01|lb-02|web-01|web-02) ;; *) echo 'Choose lb-01, lb-02, web-01 or web-02' >&2; exit 2;; esac
    vagrant ssh "$1" -c 'bash /vagrant/scripts/server-report.sh'

# Start/stop/restart/status of React: just service web-01 restart.
@service vm action:
    case "$1" in web-01|web-02) ;; *) echo 'Choose web-01 or web-02' >&2; exit 2;; esac
    case "$2" in start|stop|restart|status) ;; *) echo 'Use start, stop, restart or status' >&2; exit 2;; esac
    vagrant ssh "$1" -c "sudo bash /vagrant/scripts/service-manager.sh $2"

# Recent React service logs: just logs-web [vm].
@logs-web vm="web-01":
    case "$1" in web-01|web-02) ;; *) echo 'Choose web-01 or web-02' >&2; exit 2;; esac
    vagrant ssh "$1" -c 'sudo journalctl -u react-app -n 50 --no-pager'

# Recent LB logs: just logs-lb [vm] [haproxy|keepalived].
@logs-lb vm="lb-01" service="keepalived":
    case "$1" in lb-01|lb-02) ;; *) echo 'Choose lb-01 or lb-02' >&2; exit 2;; esac
    case "$2" in haproxy|keepalived) ;; *) echo 'Choose haproxy or keepalived' >&2; exit 2;; esac
    vagrant ssh "$1" -c "sudo journalctl -u $2 -n 50 --no-pager"

# -------- Controlled failure tests (lab environment only) --------

# Stop React on one backend: just fail-web [web-01|web-02].
@fail-web vm="web-01":
    case "$1" in web-01|web-02) ;; *) echo 'Choose web-01 or web-02' >&2; exit 2;; esac
    vagrant ssh "$1" -c 'sudo systemctl stop react-app'

# Restore a stopped React backend: just recover-web [web-01|web-02].
@recover-web vm="web-01":
    case "$1" in web-01|web-02) ;; *) echo 'Choose web-01 or web-02' >&2; exit 2;; esac
    vagrant ssh "$1" -c 'sudo systemctl start react-app'

# Stop HAProxy on an LB to test VIP failover: just fail-lb [lb-01|lb-02].
@fail-lb vm="lb-01":
    case "$1" in lb-01|lb-02) ;; *) echo 'Choose lb-01 or lb-02' >&2; exit 2;; esac
    vagrant ssh "$1" -c 'sudo systemctl stop haproxy'

# Restore HAProxy on an LB: just recover-lb [lb-01|lb-02].
@recover-lb vm="lb-01":
    case "$1" in lb-01|lb-02) ;; *) echo 'Choose lb-01 or lb-02' >&2; exit 2;; esac
    vagrant ssh "$1" -c 'sudo systemctl start haproxy'

# Delete all four VMs and their contents (requires explicit confirmation).
@destroy confirmation:
    if [[ "$1" != DESTROY ]]; then echo 'To delete all VMs, run: just destroy DESTROY' >&2; exit 2; fi
    vagrant destroy -f
