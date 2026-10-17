#!/usr/bin/env bash
# Run inside either LB VM: sudo bash /vagrant/scripts/setup-lb.sh
# Installs HAProxy + Keepalived and applies node-specific configs from Git.
set -Eeuo pipefail

REPO_ROOT="${REPO_ROOT:-/vagrant}"
NETWORK_IF="${NETWORK_IF:-eth1}"
LB_NAME="$(hostname -s)"

log() { printf '[setup-lb][%s] %s\n' "$LB_NAME" "$*"; }
fail() { printf '[setup-lb][%s] ERROR: %s\n' "$LB_NAME" "$*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || fail 'Run as root with sudo'

case "$LB_NAME" in
  lb-01)
    NODE_IP='192.168.56.10'
    HAPROXY_SOURCE="$REPO_ROOT/haproxy/lb-01.cfg"
    KEEPALIVED_SOURCE="$REPO_ROOT/keepalived/lb01.conf"
    ;;
  lb-02)
    NODE_IP='192.168.56.11'
    HAPROXY_SOURCE="$REPO_ROOT/haproxy/lb-02.cfg"
    KEEPALIVED_SOURCE="$REPO_ROOT/keepalived/lb02.conf"
    ;;
  *) fail "Expected hostname lb-01 or lb-02, got $LB_NAME" ;;
esac

[[ -f "$HAPROXY_SOURCE" ]] || fail "Missing $HAPROXY_SOURCE"
[[ -f "$KEEPALIVED_SOURCE" ]] || fail "Missing $KEEPALIVED_SOURCE"

command -v ip >/dev/null || fail 'iproute2 is required'
ip -4 -o addr show dev "$NETWORK_IF" | grep -Fq "inet $NODE_IP/" \
  || fail "Expected $NODE_IP on $NETWORK_IF. Inspect: ip -br addr"

log 'Installing HAProxy and Keepalived (Ubuntu APT)'
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y haproxy keepalived curl

log 'Checking repository configurations before replacing installed files'
haproxy -c -f "$HAPROXY_SOURCE"
keepalived --config-test -f "$KEEPALIVED_SOURCE"

backup_dir="/var/backups/ha-react/$(date -u +%Y%m%dT%H%M%SZ)-${LB_NAME}"
install -d -m 0700 "$backup_dir"
if [[ -f /etc/haproxy/haproxy.cfg ]]; then
  cp -a /etc/haproxy/haproxy.cfg "$backup_dir/haproxy.cfg"
fi
if [[ -f /etc/keepalived/keepalived.conf ]]; then
  cp -a /etc/keepalived/keepalived.conf "$backup_dir/keepalived.conf"
fi
log "Backed up previous configurations in $backup_dir"

install -m 0644 -o root -g root "$HAPROXY_SOURCE" /etc/haproxy/haproxy.cfg
install -d -m 0755 /etc/keepalived
install -m 0600 -o root -g root "$KEEPALIVED_SOURCE" /etc/keepalived/keepalived.conf

# Validate once more using the installed file paths.
haproxy -c -f /etc/haproxy/haproxy.cfg
keepalived --config-test -f /etc/keepalived/keepalived.conf

log 'Enabling and reloading HAProxy'
systemctl enable haproxy
if systemctl is-active --quiet haproxy; then
  systemctl reload haproxy
else
  systemctl start haproxy
fi
systemctl is-active --quiet haproxy || fail 'HAProxy did not become active'

log 'Enabling and restarting Keepalived to load updated VRRP settings'
systemctl enable keepalived
systemctl restart keepalived
systemctl is-active --quiet keepalived || fail 'Keepalived did not become active'

log 'Checking local HTTP proxy and header'
curl -fsSI --max-time 6 http://127.0.0.1/health \
  | grep -Fiq "x-load-balancer: ${LB_NAME^^}" \
  || fail 'The local HTTP response is unhealthy or is missing X-Load-Balancer'

log 'Services active. Check VIP ownership using: ip -4 addr show dev '$NETWORK_IF
log 'Expected VIP 192.168.56.100 on only ONE load balancer.'
