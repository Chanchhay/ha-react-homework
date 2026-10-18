#!/usr/bin/env bash
# VM-side bonus helper: stage|activate RELEASE_ID
set -Eeuo pipefail
[[ "$EUID" -eq 0 ]] || { echo 'Use sudo' >&2; exit 1; }
[[ $# -eq 2 ]] || { echo 'Usage: install-release.sh stage|activate RELEASE' >&2; exit 64; }
mode="$1"; id="$2"
case "$mode" in stage|activate) ;; *) exit 64 ;; esac
[[ "$id" =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]*$ ]] || { echo 'Invalid release ID' >&2; exit 64; }
root=/opt/react-app
release="$root/releases/$id"
user=reactapp
check_health() {
  for ((i=0;i<20;i++)); do
    if curl --fail --silent --max-time 2 http://127.0.0.1:3000/health >/dev/null; then
      return 0
    fi
    sleep 1
  done
  return 1
}
case "$mode" in
  stage)
    src="/vagrant/.artifacts/releases/$id"
    [[ -f "$src/dist/index.html" && -f "$src/server.mjs" && -f "$src/package-lock.json" && -f "$src/package.json" ]] || {
      echo "Missing release artifact in $src" >&2; exit 1;
    }
    if [[ -d "$release" ]]; then
      echo "Release $id already staged on $(hostname -s)"; exit 0
    fi
    install -d -m 0755 -o "$user" -g "$user" "$root/releases"
    tmp="${release}.staging.$$"
    trap 'rm -rf -- "$tmp"' EXIT
    install -d -m 0755 -o "$user" -g "$user" "$tmp"
    cp -a "$src/dist" "$src/server.mjs" "$src/package.json" "$src/package-lock.json" "$tmp/"
    chown -R "$user:$user" "$tmp"
    ( cd "$tmp" && runuser -u "$user" -- npm ci --omit=dev --no-audit --no-fund )
    mv -T "$tmp" "$release"
    echo "Release $id staged on $(hostname -s)"
    ;;
  activate)
    [[ -f "$release/server.mjs" && -d "$release/node_modules" ]] || { echo "Release not staged: $id" >&2; exit 1; }
    [[ -L "$root/current" ]] || { echo 'Run bootstrap-bonus before deploying' >&2; exit 1; }
    previous="$(readlink "$root/current")"
    if [[ "$previous" == "releases/$id" ]]; then
      check_health && { echo "Already using $id"; exit 0; }
      echo "Release $id is active but unhealthy" >&2; exit 1
    fi
    ln -s "releases/$id" "$root/.current.new.$$"
    mv -Tf "$root/.current.new.$$" "$root/current"
    if systemctl restart react-app && check_health; then
      echo "Activated $id on $(hostname -s)"; exit 0
    fi
    echo "New release failed /health; restoring $previous" >&2
    ln -s "$previous" "$root/.current.new.$$"
    mv -Tf "$root/.current.new.$$" "$root/current"
    systemctl restart react-app
    check_health || { echo 'CRITICAL: previous release did not recover; leave backend drained' >&2; exit 1; }
    echo 'Previous release recovered, new release rejected' >&2
    exit 1
    ;;
esac
