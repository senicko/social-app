#!/usr/bin/env bash

# Runs at the start of every Cursor cloud agent run, before the terminals.
#
#   1. Local Bluesky network (Postgres, Redis, dev-env mock server), seeded. The
#      appview DID is written to .env so the Metro terminal inlines it.
#
#   2. Argent Cloud: lease a runner, make sure our own simulator exists on it
#      (created on first use, reused afterwards), boot it, and tunnel this VM's
#      Metro (8081) and mock PDS (3000) into it as the simulator's localhost.
#
# Writes .cursor/cloud/session.env (SIM_UDID, MOCK_*) for the agent.
# Secrets: SIM_ROUTER_USERNAME, SIM_ROUTER_API_KEY.
# Optional: SIM_DEVICE_TYPE (default "iPhone 17 Pro"; falls back to the newest
#           iPhone Pro the runner's Xcode knows).

set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

: "${SIM_ROUTER_USERNAME:?Cursor secret SIM_ROUTER_USERNAME is missing}"
: "${SIM_ROUTER_API_KEY:?Cursor secret SIM_ROUTER_API_KEY is missing}"

SIM_NAME=cloud-agent
DEVICE_TYPE="${SIM_DEVICE_TYPE:-iPhone 17 Pro}"

bash .cursor/cloud/mock-backend.sh start
sim-remote login --timeout 300

# Our simulator, by name. Runners are reused between leases, so it usually
# already exists; otherwise create it from the newest available iOS runtime.
UDID="$(sim-remote simctl list devices --json \
  | jq -r --arg n "$SIM_NAME" '[.devices[][] | select(.name == $n and .isAvailable != false)][0].udid // empty')"

if [ -z "$UDID" ]; then
  runtime="$(sim-remote simctl list runtimes --json \
    | jq -r '[.runtimes[] | select(.platform == "iOS" and .isAvailable)] | sort_by(.version | split(".") | map(tonumber)) | last | .identifier // empty')"

  devtype="$(sim-remote simctl list devicetypes --json \
    | jq -r --arg n "$DEVICE_TYPE" '(.devicetypes[] | select(.name == $n) | .identifier) // empty')"

  if [ -z "$devtype" ]; then
    devtype="$(sim-remote simctl list devicetypes --json \
      | jq -r '[.devicetypes[] | select(.name | test("^iPhone [0-9]+( Pro)?$")) | {identifier, n: (.name | capture("iPhone (?<n>[0-9]+)").n | tonumber), pro: (.name | endswith("Pro"))}] | sort_by(.n, .pro) | last | .identifier // empty')"
    echo "Device type '$DEVICE_TYPE' is not on this runner; using $devtype"
  fi

  [ -n "$runtime" ] && [ -n "$devtype" ] || { echo "No available iOS runtime or iPhone device type on the leased runner" >&2; exit 1; }

  echo "Creating simulator $SIM_NAME ($devtype, $runtime)"
  UDID="$(sim-remote simctl create "$SIM_NAME" "$devtype" "$runtime")"
fi

sim-remote simctl boot "$UDID" 2>/dev/null || true   # already booted is fine
sim-remote simctl bootstatus "$UDID" -b

for port in 8081 3000; do
  sim-remote reverse status | grep -q "$UDID.*[[:space:]]$port\$" || sim-remote reverse start "$UDID" "$port"
done

sim-remote reverse status
{ echo "SIM_UDID=$UDID"; cat .cursor/cloud/mock.env; } > .cursor/cloud/session.env
echo "Simulator $SIM_NAME ($UDID) is booted; it reaches Metro at localhost:8081 and the mock PDS at localhost:3000."
