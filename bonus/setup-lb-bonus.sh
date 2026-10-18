#!/usr/bin/env bash
# Run as root on a LB VM. Always renders bonus HAProxy config from the BASE repo.
set -Eeuo pipefail
[[ "$EUID" -eq 0 ]] || { echo 'Run with sudo' >&2; exit 1; }
vm="$(hostname -s)"
case "$vm" in
  lb-01) ip=192.168.56.10 ;;
  lb-02) ip=192.168.56.11 ;;
  *) echo "Not a load-balancer: $vm" >&2; exit 1 ;;
esac
base="/vagrant/haproxy/${vm}.cfg"
[[ -f "$base" ]] || { echo "Missing $base" >&2; exit 1; }
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y haproxy socat openssl curl
install -d -o root -g root -m 0700 /etc/ha-react
secret=/etc/ha-react/monitoring-password
if [[ ! -s "$secret" ]]; then
  umask 077
  openssl rand -hex 24 > "$secret"
fi
chmod 0600 "$secret"
# OpenSSL hashes the password from standard input; the plaintext stays outside Git.
hash="$(openssl passwd -6 -stdin < "$secret")"
install -d -m 0755 /run/haproxy
# Keep config generation deterministic and avoid duplicate blocks on re-runs.
tmp="$(mktemp /tmp/haproxy-bonus.XXXXXX)"
trap 'rm -f "$tmp"' EXIT
awk '
  /^global[[:space:]]*$/ {print; print "    stats socket /run/haproxy/admin.sock mode 600 level admin"; print "    stats timeout 30s"; next}
  {print}
' "$base" > "$tmp"
cat >> "$tmp" <<CFG

# Bonus: authenticated statistics only on the management-facing host-only address
userlist monitoring_users
    user viewer password $hash

listen ha_statistics
    bind $ip:8404
    mode http
    acl lab_subnet src 192.168.56.0/24
    http-request deny unless lab_subnet
    stats enable
    stats uri /haproxy-stats
    stats refresh 5s
    stats http-request auth unless { http_auth(monitoring_users) }
CFG
haproxy -c -f "$tmp"
install -d -m 0700 /var/backups/ha-react
cp -a /etc/haproxy/haproxy.cfg "/var/backups/ha-react/haproxy-before-bonus-${vm}.cfg"
install -m 0600 -o root -g root "$tmp" /etc/haproxy/haproxy.cfg
haproxy -c -f /etc/haproxy/haproxy.cfg
systemctl reload haproxy
systemctl is-active --quiet haproxy
for attempt in 1 2 3 4 5 6; do
  if [[ -S /run/haproxy/admin.sock ]] &&
     printf 'show info\n' | socat - UNIX-CONNECT:/run/haproxy/admin.sock | grep -q '^Name:'; then
    break
  fi
  sleep 1
done
[[ -S /run/haproxy/admin.sock ]] || { echo 'HAProxy runtime socket did not appear' >&2; exit 1; }
status="$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "http://${ip}:8404/haproxy-stats")"
[[ "$status" == 401 ]] || { echo "Expected HTTP 401 without stats login, got $status" >&2; exit 1; }
echo "[bonus][$vm] HAProxy runtime API ready; protected stats on http://${ip}:8404/haproxy-stats"
