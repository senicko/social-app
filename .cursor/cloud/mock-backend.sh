#!/usr/bin/env bash
# Local Bluesky network for the cloud agent: Postgres (:5433, role pg/password),
# Redis (:6380) and the dev-env mock server (manager :1986, PDS :3000). Same
# services Bluesky's CI uses through `pnpm --dir dev-env start:external`.
#   mock-backend.sh start   bring everything up (idempotent) and seed
#   mock-backend.sh seed    rebuild the seeded network and rewrite the DID in .env
# Users alice.test / bob.test / carla.test, password hunter2 (fixture in
# dev-env/test-pds.ts). Seed query: MOCK_SEED (default users&follows&posts&thread&feeds).
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

# Cursor prepends its own /exec-daemon/node (v22) to PATH; prefer the image's Node 24.
export PATH="/usr/bin:$PATH"
export NODE_ENV=development PGHOST=localhost PGPORT=5433 PGUSER=pg PGPASSWORD=password PGDATABASE=postgres
export DB_POSTGRES_URL=postgresql://pg:password@127.0.0.1:5433/postgres REDIS_HOST=127.0.0.1:6380

wait_for() { # wait_for <seconds> <command...>
  local n=$1; shift
  until "$@" >/dev/null 2>&1; do n=$((n - 1)); [ "$n" -gt 0 ] || { echo "timed out waiting for: $*" >&2; exit 1; }; sleep 1; done
}

start() {
  local v; v="$(ls /etc/postgresql | sort -V | tail -1)"
  [ -d "/etc/postgresql/$v/bsky" ] || sudo pg_createcluster "$v" bsky -p 5433 >/dev/null
  sudo pg_ctlcluster "$v" bsky start 2>/dev/null || true
  wait_for 30 sudo -u postgres pg_isready -q -p 5433
  sudo -u postgres psql -p 5433 -tAc "SELECT 1 FROM pg_roles WHERE rolname='pg'" | grep -q 1 \
    || sudo -u postgres psql -p 5433 -qc "CREATE ROLE pg LOGIN SUPERUSER PASSWORD 'password'"
  redis-cli -p 6380 ping >/dev/null 2>&1 \
    || redis-server --port 6380 --daemonize yes --save "" --appendonly no >/dev/null
  if ! curl -fs -o /dev/null http://localhost:1986/; then
    (cd dev-env && nohup node ./mock-server.ts >../.cursor/cloud/mock-server.log 2>&1 &)
    wait_for 60 curl -fs -o /dev/null http://localhost:1986/
  fi
  seed
}

seed() {
  local resp did
  resp="$(curl -fsS -m 900 -X POST "http://localhost:1986/?${MOCK_SEED:-users&follows&posts&thread&feeds}")"
  did="$(printf '%s' "$resp" | jq -r '.appviewDid // empty')"
  [ -n "$did" ] || { echo "seed failed: $resp" >&2; exit 1; }
  [ -f .env ] || cp .env.example .env
  sed -i.bak "s|^EXPO_PUBLIC_BLUESKY_PROXY_DID=.*|EXPO_PUBLIC_BLUESKY_PROXY_DID=$did|" .env && rm -f .env.bak
  printf 'MOCK_PDS_URL=http://localhost:3000\nMOCK_APPVIEW_DID=%s\nMOCK_USER=alice.test\n' "$did" > .cursor/cloud/mock.env
  wait_for 30 curl -fs http://localhost:3000/xrpc/_health
  echo "mock network ready: PDS http://localhost:3000, appview $did (written to .env)"
}

case "${1:-}" in
  start) start ;;
  seed) seed ;;
  *) echo "usage: $0 start|seed" >&2; exit 2 ;;
esac
