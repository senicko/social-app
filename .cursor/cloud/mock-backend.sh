#!/usr/bin/env bash
# Local Bluesky network for the cloud agent: Postgres + Redis + the dev-env mock
# server (PDS on :3000, manager on :1986), seeded with alice/bob/carla. This is
# what Bluesky's nightly e2e job runs on macOS runners via
# `pnpm --dir dev-env start:external`; here the services are native Ubuntu
# packages, no Docker.
#
#   mock-backend.sh services   start Postgres (:5433, role pg/password) and Redis (:6380)
#   mock-backend.sh start      services, mock server in the background, seed, write .env
#   mock-backend.sh seed       recreate the test network; rewrite EXPO_PUBLIC_BLUESKY_PROXY_DID
#   mock-backend.sh status
#   mock-backend.sh stop
#
# Seeded users: alice.test, bob.test, carla.test; password "hunter2" (fixture in
# dev-env/test-pds.ts). Every `seed` rebuilds the whole network and mints a new
# appview DID; it came out identical across machines and reseeds (the dev-env
# keys are fixed), but the script rewrites .env every time in case that changes.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
ROOT="$PWD"

PG_PORT=5433
REDIS_PORT=6380
MANAGER_PORT=1986
PDS_PORT=3000
SEED_QUERY="${MOCK_SEED:-users&follows&posts&thread&feeds}"

LOG="$ROOT/.cursor/cloud/mock-server.log"
PIDFILE="$ROOT/.cursor/cloud/.mock-server.pid"
MOCK_ENV="$ROOT/.cursor/cloud/mock.env"

# Same variables dev-env/dev-infra/_common.sh exports for `pnpm start`.
export NODE_ENV=development
export PGPORT="$PG_PORT" PGHOST=localhost PGUSER=pg PGPASSWORD=password PGDATABASE=postgres
export DB_POSTGRES_URL="postgresql://pg:password@127.0.0.1:$PG_PORT/postgres"
export REDIS_HOST="127.0.0.1:$REDIS_PORT"

pg_version() { ls /etc/postgresql 2>/dev/null | sort -V | tail -1; }

services() {
  local v; v="$(pg_version)"
  [ -n "$v" ] || { echo "postgresql is not installed (the Dockerfile installs it)" >&2; exit 1; }
  # A dedicated cluster on 5433 so nothing collides with the package's default one.
  if [ ! -d "/etc/postgresql/$v/bsky" ]; then
    sudo pg_createcluster "$v" bsky -p "$PG_PORT" >/dev/null
  fi
  sudo pg_ctlcluster "$v" bsky start 2>/dev/null || true
  for _ in $(seq 1 30); do
    sudo -u postgres pg_isready -q -p "$PG_PORT" && break
    sleep 1
  done
  if ! sudo -u postgres psql -p "$PG_PORT" -tAc "SELECT 1 FROM pg_roles WHERE rolname='pg'" | grep -q 1; then
    sudo -u postgres psql -p "$PG_PORT" -qc "CREATE ROLE pg LOGIN SUPERUSER PASSWORD 'password'"
  fi
  psql -h 127.0.0.1 -qtAc "SELECT 'postgres ready on :$PG_PORT'"

  if ! redis-cli -p "$REDIS_PORT" ping >/dev/null 2>&1; then
    redis-server --port "$REDIS_PORT" --daemonize yes --save "" --appendonly no \
      --logfile "$ROOT/.cursor/cloud/redis.log" >/dev/null
    for _ in $(seq 1 20); do redis-cli -p "$REDIS_PORT" ping >/dev/null 2>&1 && break; sleep 1; done
  fi
  echo "redis ready on :$REDIS_PORT ($(redis-cli -p "$REDIS_PORT" ping))"
}

server_running() {
  [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null \
    && curl -fs -o /dev/null "http://localhost:$MANAGER_PORT/"
}

start_server() {
  if server_running; then
    echo "mock server manager already running (pid $(cat "$PIDFILE"))"
    return
  fi
  if [ ! -d dev-env/node_modules ]; then
    (cd dev-env && pnpm install --frozen-lockfile)
  fi
  (cd dev-env && nohup node ./mock-server.ts >"$LOG" 2>&1 & echo $! >"$PIDFILE")
  for _ in $(seq 1 60); do
    curl -fs -o /dev/null "http://localhost:$MANAGER_PORT/" && break
    kill -0 "$(cat "$PIDFILE")" 2>/dev/null || { echo "mock server exited; log:" >&2; cat "$LOG" >&2; exit 1; }
    sleep 1
  done
  curl -fs -o /dev/null "http://localhost:$MANAGER_PORT/" || { echo "mock server manager did not come up on :$MANAGER_PORT" >&2; tail -20 "$LOG" >&2; exit 1; }
  echo "mock server manager listening on :$MANAGER_PORT (log: $LOG)"
}

seed() {
  echo "Seeding test network ($SEED_QUERY)"
  local resp did pds
  resp="$(curl -fsS -m 900 -X POST "http://localhost:$MANAGER_PORT/?$SEED_QUERY")"
  did="$(printf '%s' "$resp" | jq -r '.appviewDid // empty')"
  pds="$(printf '%s' "$resp" | jq -r '.pdsUrl // empty')"
  [ -n "$did" ] && [ -n "$pds" ] || { echo "unexpected seed response: $resp" >&2; exit 1; }

  [ -f .env ] || cp .env.example .env
  if grep -q '^EXPO_PUBLIC_BLUESKY_PROXY_DID=' .env; then
    sed -i.bak "s|^EXPO_PUBLIC_BLUESKY_PROXY_DID=.*|EXPO_PUBLIC_BLUESKY_PROXY_DID=$did|" .env && rm -f .env.bak
  else
    printf '\nEXPO_PUBLIC_BLUESKY_PROXY_DID=%s\n' "$did" >> .env
  fi
  {
    echo "MOCK_PDS_URL=$pds"
    echo "MOCK_APPVIEW_DID=$did"
    echo "MOCK_USER=alice.test"
  } > "$MOCK_ENV"
  curl -fs "http://localhost:$PDS_PORT/xrpc/_health" >/dev/null && echo "PDS healthy at $pds"
  echo "EXPO_PUBLIC_BLUESKY_PROXY_DID=$did written to .env (Metro must start after this)"
}

status() {
  psql -h 127.0.0.1 -qtAc "SELECT 'postgres :$PG_PORT ok'" 2>/dev/null || echo "postgres :$PG_PORT DOWN"
  echo "redis :$REDIS_PORT $(redis-cli -p "$REDIS_PORT" ping 2>/dev/null || echo DOWN)"
  if server_running; then echo "mock server manager :$MANAGER_PORT ok (pid $(cat "$PIDFILE"))"; else echo "mock server manager :$MANAGER_PORT DOWN"; fi
  curl -fs "http://localhost:$PDS_PORT/xrpc/_health" >/dev/null 2>&1 && echo "PDS :$PDS_PORT ok" || echo "PDS :$PDS_PORT DOWN (run: mock-backend.sh seed)"
  [ -f "$MOCK_ENV" ] && cat "$MOCK_ENV" || true
}

stop() {
  if [ -f "$PIDFILE" ]; then
    local pid; pid="$(cat "$PIDFILE")"
    kill "$pid" 2>/dev/null || true
    for _ in $(seq 1 10); do kill -0 "$pid" 2>/dev/null || break; sleep 1; done
    kill -9 "$pid" 2>/dev/null || true
    rm -f "$PIDFILE"
  fi
  pkill -f "node ./mock-server.ts" 2>/dev/null || true
  redis-cli -p "$REDIS_PORT" shutdown nosave >/dev/null 2>&1 || true
  local v; v="$(pg_version)"
  [ -n "$v" ] && sudo pg_ctlcluster "$v" bsky stop 2>/dev/null || true
  rm -f "$MOCK_ENV"
  echo "mock backend stopped"
}

case "${1:-}" in
  services) services ;;
  start)    services; start_server; seed ;;
  seed)     seed ;;
  status)   status ;;
  stop)     stop ;;
  *) echo "usage: $0 services|start|seed|status|stop" >&2; exit 2 ;;
esac
