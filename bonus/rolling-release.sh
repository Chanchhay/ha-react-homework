#!/usr/bin/env bash
# Host orchestration: init | deploy RELEASE | rollback RELEASE
# HAProxy is drained on BOTH LBs before each systemd restart.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
[[ $# -ge 1 && $# -le 2 ]] || { echo 'Usage: rolling-release.sh init|deploy|rollback [RELEASE]' >&2; exit 64; }
mode="$1"; id="${2:-}"
case "$mode" in
  init) [[ $# == 1 ]] || exit 64 ;;
  deploy|rollback) [[ $# == 2 && "$id" =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]*$ ]] || exit 64 ;;
  *) echo 'Unknown mode' >&2; exit 64 ;;
esac
command -v vagrant >/dev/null || { echo 'Missing Vagrant' >&2; exit 1; }
current_vm=''
current_backend=''
lb_run() {
  local lb="$1" command="$2" backend="$3"
  vagrant ssh "$lb" -c "sudo bash /vagrant/bonus/lb-control.sh $command $backend"
}
vm_run() {
  local vm="$1" command="$2" release="${3:-}"
  case "$command" in
    init) vagrant ssh "$vm" -c 'sudo bash /vagrant/bonus/init-release.sh' ;;
    stage|activate) vagrant ssh "$vm" -c "sudo bash /vagrant/bonus/install-release.sh $command $release" ;;
  esac
}
healthy_direct() {
  local vm="$1" ip
  case "$vm" in web-01) ip=192.168.56.20 ;; web-02) ip=192.168.56.21 ;; esac
  curl --fail --silent --max-time 3 "http://$ip:3000/health" >/dev/null
}
on_exit() {
  local rc=$?
  if [[ -n "$current_vm" ]]; then
    if healthy_direct "$current_vm"; then
      echo "[bonus] Recovering HAProxy routing for $current_backend" >&2
      for lb in lb-01 lb-02; do
        lb_run "$lb" ready "$current_backend" || echo "[bonus] WARNING: Could not restore $current_backend on $lb" >&2
      done
    else
      echo "[bonus] IMPORTANT: $current_vm remains unhealthy; leaving it drained." >&2
    fi
  fi
  exit "$rc"
}
trap on_exit EXIT

# Pre-stage the new app on BOTH VMs without interrupting the running service.
if [[ "$mode" == deploy ]]; then
  [[ -f ".artifacts/releases/$id/dist/index.html" ]] || { echo "Missing .artifacts/releases/$id; run deploy-github" >&2; exit 1; }
  for vm in web-01 web-02; do
    echo "[bonus] Staging $id on $vm"
    vm_run "$vm" stage "$id"
  done
fi
if [[ "$mode" == rollback ]]; then
  for vm in web-01 web-02; do
    vagrant ssh "$vm" -c "test -d /opt/react-app/releases/$id" || {
      echo "Release $id is not installed on $vm" >&2; exit 1;
    }
  done
fi

for vm in web-01 web-02; do
  case "$vm" in
    web-01) backend=web01; other=web02 ;;
    web-02) backend=web02; other=web01 ;;
  esac
  echo "[bonus] Checking that $other can serve traffic during $vm maintenance"
  healthy_direct "$vm" || { echo "Current backend $vm is unhealthy before maintenance" >&2; exit 1; }
  for lb in lb-01 lb-02; do lb_run "$lb" check-up "$other"; done

  current_vm="$vm"; current_backend="$backend"
  echo "[bonus] Draining $backend on BOTH load balancers"
  for lb in lb-01 lb-02; do lb_run "$lb" drain "$backend"; done
  for lb in lb-01 lb-02; do lb_run "$lb" wait-empty "$backend"; done

  echo "[bonus] Applying ${mode} to $vm"
  if [[ "$mode" == init ]]; then
    vm_run "$vm" init
  else
    vm_run "$vm" activate "$id"
  fi
  healthy_direct "$vm"
  echo "[bonus] Restoring $backend on BOTH load balancers"
  for lb in lb-01 lb-02; do lb_run "$lb" ready "$backend"; done
  for lb in lb-01 lb-02; do lb_run "$lb" wait-up "$backend"; done
  current_vm=''; current_backend=''
done

echo "[bonus] $mode completed for both web servers"
