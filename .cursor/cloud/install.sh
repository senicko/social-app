#!/usr/bin/env bash
# Cursor cloud agent "install" step. Runs from the repo root when the
# environment is built (and again on partially cached state), so everything
# here must be idempotent. See docs/cloud-agent-plan.md.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

echo "node $(node -v) / pnpm $(pnpm -v) / eas $(eas --version 2>/dev/null | tail -1) / gh $(gh --version | head -1)"

# App dependencies. postinstall generates lexicons and compiles i18n if needed.
pnpm install --frozen-lockfile

# Mock backend dependencies (separate pnpm workspace under dev-env/).
(cd dev-env && pnpm install --frozen-lockfile)

# Local-only config files the app and prebuild expect. Both are gitignored.
# start.sh rewrites EXPO_PUBLIC_BLUESKY_PROXY_DID in .env on every run.
[ -f .env ] || cp .env.example .env
[ -f google-services.json ] || cp google-services.json.example google-services.json

# Argent Cloud client, from the public release hardcoded in the script.
if ! bash .cursor/cloud/ensure-sim-remote.sh; then
  echo "WARNING: sim-remote is not installed yet; start.sh will try again." >&2
fi

# gh >= 2.99 is required for `gh pr create --attach` (PR media upload).
ghv="$(gh --version | head -1 | sed -E 's/.* ([0-9]+\.[0-9]+)\.[0-9]+.*/\1/')"
if [ "$(printf '%s\n' 2.99 "$ghv" | sort -V | head -1)" != "2.99" ]; then
  echo "WARNING: gh $ghv is older than 2.99; --attach will not work" >&2
fi

# Postgres and Redis must be installed in the image; the cluster itself is
# created on first start by mock-backend.sh.
command -v pg_createcluster >/dev/null || echo "WARNING: postgresql is not installed; mock-backend.sh will fail" >&2
command -v redis-server >/dev/null || echo "WARNING: redis-server is not installed; mock-backend.sh will fail" >&2

echo "install.sh done"
