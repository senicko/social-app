#!/usr/bin/env bash
# Cursor cloud agent "start" step: runs at the beginning of every agent run,
# from the repo root, before the terminals. It
#   1. brings up the local Bluesky network (Postgres, Redis, dev-env mock server),
#      seeds it and writes the appview DID into .env so Metro inlines it;
#   2. leases an Argent Cloud runner, boots a simulator and tunnels this VM's
#      Metro (:8081) and mock PDS (:3000) into it.
# Writes .cursor/cloud/session.env for the agent and the other scripts.
#
# Required secrets: SIM_ROUTER_USERNAME, SIM_ROUTER_API_KEY
# Optional:         SIM_DEVICE_NAME (default "iPhone 17 Pro"), SIM_UDID,
#                   SIM_LOGIN_TIMEOUT (seconds, default 300), MOCK_SEED
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

bash .cursor/cloud/ensure-sim-remote.sh

: "${SIM_ROUTER_USERNAME:?Cursor secret SIM_ROUTER_USERNAME is missing}"
: "${SIM_ROUTER_API_KEY:?Cursor secret SIM_ROUTER_API_KEY is missing}"

DEVICE_NAME="${SIM_DEVICE_NAME:-iPhone 17 Pro}"
METRO_PORT="${METRO_PORT:-8081}"
PDS_PORT=3000

# 1. Local Bluesky network. Must finish before the metro terminal starts,
#    because EXPO_PUBLIC_* values are inlined into the bundle.
bash .cursor/cloud/mock-backend.sh start

# 2. Argent Cloud simulator.
echo "Logging in to Argent Cloud and leasing a runner (timeout ${SIM_LOGIN_TIMEOUT:-300}s)"
sim-remote login --timeout "${SIM_LOGIN_TIMEOUT:-300}"
sim-remote list-machines

UDID="${SIM_UDID:-}"
if [ -z "$UDID" ]; then
  UDID="$(sim-remote simctl list devices available --json \
    | jq -r --arg n "$DEVICE_NAME" \
        '[.devices[][] | select(.isAvailable != false and .name == $n)][0].udid // empty')"
fi
if [ -z "$UDID" ]; then
  echo "No available simulator named '$DEVICE_NAME' on the leased runner. Available devices:" >&2
  sim-remote simctl list devices available >&2
  exit 1
fi

state="$(sim-remote simctl list devices --json \
  | jq -r --arg u "$UDID" '.devices[][] | select(.udid == $u) | .state')"
if [ "$state" != "Booted" ]; then
  echo "Booting $DEVICE_NAME ($UDID)"
  sim-remote simctl boot "$UDID"
fi
sim-remote simctl bootstatus "$UDID" -b

# Simulator's localhost:<port> -> this VM. 8081 is Metro, 3000 is the mock PDS.
ensure_reverse() {
  if ! sim-remote reverse status | grep -q "$UDID.*[[:space:]]$1\$"; then
    sim-remote reverse start "$UDID" "$1"
  fi
}
ensure_reverse "$METRO_PORT"
ensure_reverse "$PDS_PORT"
sim-remote reverse status

{
  echo "SIM_UDID=$UDID"
  # Quote the name: unquoted "iPhone 17 Pro" breaks `source session.env`.
  printf 'SIM_DEVICE_NAME=%q\n' "$DEVICE_NAME"
  echo "METRO_PORT=$METRO_PORT"
  echo "PDS_PORT=$PDS_PORT"
  cat .cursor/cloud/mock.env
} > .cursor/cloud/session.env

echo "Simulator $DEVICE_NAME ($UDID) is booted; it reaches Metro at localhost:$METRO_PORT and the mock PDS at localhost:$PDS_PORT."
echo "Session details written to .cursor/cloud/session.env"
