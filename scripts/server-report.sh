#!/usr/bin/env bash
# Run on any Ubuntu VM: bash /vagrant/scripts/server-report.sh
set -Eeuo pipefail

fail() { printf '[server-report] ERROR: %s\n' "$*" >&2; exit 1; }
[[ $# -eq 0 ]] || fail 'This script does not accept arguments'

cpu_snapshot() {
  awk '/^cpu / {
    idle = $5 + $6;
    total = 0;
    for (i = 2; i <= NF; i++) total += $i;
    print total, idle;
    exit;
  }' /proc/stat
}

read -r total1 idle1 < <(cpu_snapshot)
sleep 1
read -r total2 idle2 < <(cpu_snapshot)
cpu_usage="$(awk -v t1="$total1" -v t2="$total2" \
                 -v i1="$idle1" -v i2="$idle2" \
  'BEGIN { delta=t2-t1; busy=delta-(i2-i1);
           if (delta>0) printf "%.1f", 100*busy/delta;
           else printf "0.0"; }')"

printf '%s\n' '========================================='
printf 'SERVER REPORT: %s\n' "$(hostname -s)"
printf '%s\n' '========================================='
printf 'Date (UTC) : %s\n' "$(date -u +'%Y-%m-%d %H:%M:%S')"
printf 'Hostname   : %s\n' "$(hostname)"
printf 'IPv4       : %s\n' "$(hostname -I 2>/dev/null || true)"
printf 'Uptime     : %s\n' "$(uptime -p)"
printf 'CPU cores  : %s\n' "$(nproc)"
printf 'CPU used   : %s%% (1-second sample)\n' "$cpu_usage"
printf 'Memory     : '
free -h | awk '/^Mem:/ {printf "used %s / total %s; available %s\n", $3, $2, $7}'
printf 'Disk (/)   : '
df -h / | awk 'NR==2 {printf "used %s / total %s (%s)\n", $3, $2, $5}'
