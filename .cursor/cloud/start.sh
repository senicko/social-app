#!/usr/bin/env bash

# Runs at the start of every Cursor cloud agent run, before the terminals.
#
#   1. Local Bluesky network (Postgres, Redis, dev-env mock server), seeded. The
#      appview DID is written to .env so the Metro terminal inlines it.
#
#   2. Argent Cloud: lease a runner, create a fresh simulator for this run
#      (cloud-agent-<random>), boot it, and tunnel this VM's Metro (8081) and
#      mock PDS (3000) into it as the simulator's localhost. Leftover
#      cloud-agent-* simulators from crashed runs on the same runner are
#      deleted first; a lease is exclusive, so they can only be ours.
#
# Writes .cursor/cloud/session.env (SIM_UDID, MOCK_*) for the agent.
# Secrets: SIM_ROUTER_USERNAME, SIM_ROUTER_API_KEY.
# Optional: SIM_DEVICE_TYPE (default "iPhone 17 Pro"; falls back to the newest
#           iPhone Pro the runner's Xcode knows).

set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

: "${SIM_ROUTER_USERNAME:?Cursor secret SIM_ROUTER_USERNAME is missing}"
: "${SIM_ROUTER_API_KEY:?Cursor secret SIM_ROUTER_API_KEY is missing}"

DEVICE_TYPE="${SIM_DEVICE_TYPE:-iPhone 17 Pro}"
SIM_NAME="cloud-agent-$(cut -c1-8 /proc/sys/kernel/random/uuid)"

bash .cursor/cloud/mock-backend.sh start
sim-remote login --timeout 300

# Sweep simulators left behind by earlier runs on this runner.
sim-remote simctl list devices --json \
  | jq -r '.devices[][] | select(.name | startswith("cloud-agent-")) | .udid' \
  | while read -r old; do
      echo "Deleting leftover simulator $old"
      sim-remote simctl shutdown "$old" 2>/dev/null || true
      sim-remote simctl delete "$old"
    done

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

sim-remote simctl boot "$UDID"
sim-remote simctl bootstatus "$UDID" -b

for port in 8081 3000; do
  sim-remote reverse start "$UDID" "$port"
done

sim-remote reverse status
{ echo "SIM_UDID=$UDID"; echo "SIM_NAME=$SIM_NAME"; cat .cursor/cloud/mock.env; } > .cursor/cloud/session.env
echo "Simulator $SIM_NAME ($UDID) is booted; it reaches Metro at localhost:8081 and the mock PDS at localhost:3000."
