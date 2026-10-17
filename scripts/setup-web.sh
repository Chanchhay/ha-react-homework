#!/usr/bin/env bash
# Run on WEB-01 and WEB-02: sudo bash /vagrant/scripts/setup-web.sh
set -Eeuo pipefail

APP_USER="reactapp"
APP_DIR="/opt/react-app"
NODE_MAJOR_REQUIRED=22

log() { printf '[setup-web] %s\n' "$*"; }
fail() { printf '[setup-web] ERROR: %s\n' "$*" >&2; exit 1; }
trap 'fail "Command failed at line $LINENO"' ERR

[[ ${EUID} -eq 0 ]] || fail "Run as root: sudo bash $0"
[[ -f /etc/os-release ]] || fail "Cannot identify the Linux distribution"
# shellcheck disable=SC1091
. /etc/os-release
[[ ${ID:-} == ubuntu ]] || fail "This script expects Ubuntu"

export DEBIAN_FRONTEND=noninteractive
log "Installing base packages"
apt-get update -qq
apt-get install -y curl ca-certificates

installed_major=0
if command -v node >/dev/null 2>&1; then
        installed_major="$(node -p 'Number(process.versions.node.split(".")[0])')"
fi

if (( installed_major < NODE_MAJOR_REQUIRED )); then
        log "Installing Node.js 22 from NodeSource"
        curl --fail --silent --show-error --location \
        https://deb.nodesource.com/setup_22.x \
        --output /tmp/nodesource_setup_22.sh
        # Inspect external setup scripts before executing in security-sensitive systems.
        bash /tmp/nodesource_setup_22.sh
        apt-get install -y nodejs
else
        log "Existing Node.js $(node --version) is sufficient"
fi

command -v npm >/dev/null 2>&1 || fail "npm is missing after Node.js installation"
if ! id "$APP_USER" >/dev/null 2>&1; then
        log "Creating non-root service account: $APP_USER"
        useradd --system --user-group --no-create-home \
        --home-dir "$APP_DIR" --shell /usr/sbin/nologin "$APP_USER"
else
        log "Account $APP_USER already exists"
fi

install -d -m 755 -o "$APP_USER" -g "$APP_USER" "$APP_DIR"
log "Ready: Node $(node --version), npm $(npm --version), user $APP_USER, directory $APP_DIR"
