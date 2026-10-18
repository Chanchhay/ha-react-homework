#!/usr/bin/env bash
# Run on host AFTER `just bootstrap`. Safe to re-run on healthy bonus deployments.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
command -v vagrant >/dev/null || { echo 'Missing vagrant' >&2; exit 1; }
echo '[bonus] Checking base infrastructure health'
bash scripts/check-health.sh --all

echo '[bonus] Configuring the BACKUP load balancer, then PRIMARY'
for lb in lb-02 lb-01; do
  echo "[bonus] $lb: enable HAProxy runtime API and protected stats"
  vagrant ssh "$lb" -c 'sudo bash /vagrant/bonus/setup-lb-bonus.sh'
done

echo '[bonus] Migrating the running application into baseline release directories'
bash bonus/rolling-release.sh init

echo '[bonus] Checking that the VIP and original endpoints still work'
bash scripts/check-health.sh --all
printf '\n[bonus] Ready. Try: just stats; just releases; just deploy-github main\n'
