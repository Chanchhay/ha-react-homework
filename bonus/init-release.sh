#!/usr/bin/env bash
# One-time conversion of a healthy BASE React service into a versioned baseline release.
# Run as root on WEB-01/WEB-02 while HAProxy has drained this backend.
set -Eeuo pipefail
[[ "$EUID" -eq 0 ]] || { echo 'Use sudo' >&2; exit 1; }
root=/opt/react-app
user=reactapp
unit=/etc/systemd/system/react-app.service
[[ -f "$root/server.mjs" && -d "$root/dist" && -d "$root/node_modules" && -f "$root/package-lock.json" ]] || {
  echo 'Base application missing. Run just bootstrap first.' >&2; exit 1;
}
[[ -f "$unit" ]] || { echo 'Missing react-app.service' >&2; exit 1; }
systemctl is-active --quiet react-app || { echo 'Base React service must be running before migration' >&2; exit 1; }

# An already-migrated, working node needs no changes. Do not overwrite its active release.
if [[ -L "$root/current" ]]; then
  if grep -q '^WorkingDirectory=/opt/react-app/current$' "$unit" &&
     grep -q '^ExecStart=/usr/bin/node /opt/react-app/current/server.mjs$' "$unit"; then
    echo "Already migrated: $(readlink "$root/current")"
    exit 0
  fi
  echo 'Existing current symlink, but systemd unit is not bonus-aware; inspect manually' >&2
  exit 1
fi
[[ ! -e "$root/current" ]] || { echo 'Refusing to overwrite non-symlink /opt/react-app/current' >&2; exit 1; }

install -d -m 0755 -o "$user" -g "$user" "$root/releases"
release="$root/releases/baseline"
if [[ ! -d "$release" ]]; then
  tmp="$root/releases/.baseline.staging.$$"
  trap 'rm -rf -- "${tmp:-}"' EXIT
  mkdir -p "$tmp"
  cp -a "$root/dist" "$root/server.mjs" "$root/node_modules" \
    "$root/package.json" "$root/package-lock.json" "$tmp/"
  chown -R "$user:$user" "$tmp"
  mv -T "$tmp" "$release"
  trap - EXIT
fi
[[ -f "$release/server.mjs" && -d "$release/node_modules" ]] || {
  echo 'Baseline release is incomplete; refusing to migrate service' >&2; exit 1;
}

# Preserve the exact original unit once and switch back if activation fails.
[[ -f "${unit}.pre-bonus" ]] || cp -a "$unit" "${unit}.pre-bonus"
restore_original() {
  local rc=$?
  if [[ "$rc" -ne 0 ]]; then
    echo 'Bonus migration failed; restoring original systemd unit' >&2
    set +e
    cp -a "${unit}.pre-bonus" "$unit"
    rm -f "$root/current" "$root/.current.new.$$"
    systemctl daemon-reload
    systemctl restart react-app
  fi
}
trap restore_original EXIT
ln -s releases/baseline "$root/.current.new.$$"
mv -Tf "$root/.current.new.$$" "$root/current"
sed -i \
  -e 's|^WorkingDirectory=/opt/react-app$|WorkingDirectory=/opt/react-app/current|' \
  -e 's|^ExecStart=/usr/bin/node /opt/react-app/server.mjs$|ExecStart=/usr/bin/node /opt/react-app/current/server.mjs|' \
  "$unit"
grep -q '^WorkingDirectory=/opt/react-app/current$' "$unit"
grep -q '^ExecStart=/usr/bin/node /opt/react-app/current/server.mjs$' "$unit"
systemctl daemon-reload
systemctl restart react-app
for ((i=0;i<20;i++)); do
  if curl -fsS --max-time 2 http://127.0.0.1:3000/health >/dev/null 2>&1; then
    echo 'Baseline release migrated successfully'
    exit 0
  fi
  sleep 1
done
echo 'Baseline release did not pass /health within 20 seconds' >&2
exit 1
