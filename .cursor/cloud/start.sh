#!/usr/bin/env bash
# Runs at the start of every Cursor cloud agent run, before the terminals.
#   1. Local Bluesky network (Postgres, Redis, dev-env mock server), seeded; the
#      appview DID is written to .env so the Metro terminal inlines it.
#   2. Argent Cloud: lease a runner, boot a simulator, tunnel this VM's Metro
#      (8081) and mock PDS (3000) into it as the simulator's localhost.
# Writes .cursor/cloud/session.env (SIM_UDID, MOCK_*) for the agent.
# Secrets: SIM_ROUTER_USERNAME, SIM_ROUTER_API_KEY. Optional: SIM_DEVICE_NAME.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
: "${SIM_ROUTER_USERNAME:?Cursor secret SIM_ROUTER_USERNAME is missing}"
: "${SIM_ROUTER_API_KEY:?Cursor secret SIM_ROUTER_API_KEY is missing}"
DEVICE="${SIM_DEVICE_NAME:-iPhone 17 Pro}"

bash .cursor/cloud/mock-backend.sh start

sim-remote login --timeout 300
UDID="$(sim-remote simctl list devices available --json \
  | jq -r --arg n "$DEVICE" '[.devices[][] | select(.name == $n)][0].udid // empty')"
[ -n "$UDID" ] || { echo "No simulator named '$DEVICE' on the leased runner:" >&2; sim-remote simctl list devices available >&2; exit 1; }
sim-remote simctl boot "$UDID" 2>/dev/null || true   # already booted is fine
sim-remote simctl bootstatus "$UDID" -b
for port in 8081 3000; do
  sim-remote reverse status | grep -q "$UDID.*[[:space:]]$port\$" || sim-remote reverse start "$UDID" "$port"
done
sim-remote reverse status

{ echo "SIM_UDID=$UDID"; cat .cursor/cloud/mock.env; } > .cursor/cloud/session.env
echo "Simulator $DEVICE ($UDID) is booted; it reaches Metro at localhost:8081 and the mock PDS at localhost:3000."
