#!/usr/bin/env bash
# Host: fetch latest GitHub origin branch, build once, roll out to both backends.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
[[ $# -le 1 ]] || { echo 'Usage: deploy-github.sh [branch]' >&2; exit 64; }
branch="${1:-main}"
[[ "$branch" =~ ^[a-zA-Z0-9][a-zA-Z0-9._/-]*$ && "$branch" != *..* ]] || {
  echo 'Invalid branch name' >&2; exit 64;
}
for cmd in git npm tar mktemp; do command -v "$cmd" >/dev/null || { echo "Missing $cmd" >&2; exit 1; }; done
[[ -f Vagrantfile ]] || { echo 'Run in project root' >&2; exit 1; }
if ! git remote get-url origin >/dev/null 2>&1; then
  echo 'GitHub origin remote is missing. Set: git remote add origin <your-repo-url>' >&2
  exit 1
fi
# Fetch without changing the local working tree or its committed base configurations.
echo "[bonus] Fetching origin/$branch"
git fetch --no-tags origin "refs/heads/$branch"
commit="$(git rev-parse --verify FETCH_HEAD^{commit})"
id="${commit:0:12}"
mkdir -p .artifacts/releases .artifacts/work
if [[ ! -d ".artifacts/releases/$id" ]]; then
  tmp="$(mktemp -d "$ROOT/.artifacts/work/build.XXXXXX")"
  trap 'rm -rf -- "$tmp"' EXIT
  git archive "$commit" react-app/ | tar -xf - -C "$tmp"
  app="$tmp/react-app"
  [[ -f "$app/package-lock.json" && -f "$app/server.mjs" ]] || {
    echo 'Git commit must include react-app/package-lock.json and server.mjs' >&2; exit 1;
  }
  echo "[bonus] Building GitHub commit $commit"
  (cd "$app" && npm ci && npm run build)
  [[ -f "$app/dist/index.html" ]] || { echo 'Build has no dist/index.html' >&2; exit 1; }
  stage="$ROOT/.artifacts/releases/.${id}.staging.$$"
  mkdir -p "$stage"
  cp -a "$app/dist" "$app/server.mjs" "$app/package.json" "$app/package-lock.json" "$stage/"
  mv -T "$stage" "$ROOT/.artifacts/releases/$id"
fi
printf '[bonus] Release %s from Git commit %s\n' "$id" "$commit"
bash bonus/rolling-release.sh deploy "$id"
