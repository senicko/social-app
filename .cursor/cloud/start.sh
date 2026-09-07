#!/usr/bin/env bash

# start.sh
#
# Runs once at the start of every Cursor cloud agent run.
# Starts before the Metro terminal.
#
# What it does
#   1. Install CURSOR-CLOUD.md as an always-on Cursor rule (gitignored)
#   2. Start and seed the mock Bluesky network
#   3. Lease an Argent Cloud runner
#   4. Create and boot a fresh cloud-agent-* simulator
#   5. Tunnel Metro (8081) and mock PDS (3000) into that simulator
#   6. Write .cursor/cloud/session.env for the agent
#
# Required secrets
#   SIM_ROUTER_USERNAME
#   SIM_ROUTER_API_KEY
#
# Argent MCP for cloud agents: register `argent mcp` as a stdio server in the
# Cursor dashboard; cloud agents ignore the repo's .cursor/mcp.json.
#
# Optional env
#   SIM_DEVICE_TYPE   Device type to create (default iPhone 17 Pro)

set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

# Cursor prepends its own Node 22 on PATH. Prefer the image Node 24.
export PATH="/usr/bin:$PATH"

# CURSOR-CLOUD.md becomes an always-on Cursor rule.
mkdir -p .cursor/rules
{ printf -- '---\nalwaysApply: true\n---\n\n'; cat .cursor/cloud/CURSOR-CLOUD.md; } > .cursor/rules/cloud-session.mdc

: "${SIM_ROUTER_USERNAME:?SIM_ROUTER_USERNAME is missing}"
: "${SIM_ROUTER_API_KEY:?SIM_ROUTER_API_KEY is missing}"

DEVICE_TYPE="${SIM_DEVICE_TYPE:-iPhone 17 Pro}"
SIM_NAME="cloud-agent-$(cut -c1-8 /proc/sys/kernel/random/uuid)"

bash .cursor/cloud/mock-backend.sh start
sim-remote login --timeout 300

# Delete shut-down cloud-agent leftovers from crashed runs.
# Skip booted ones. Those belong to a live parallel run.
sim-remote simctl list devices --json \
  | jq -r '.devices[][] | select((.name | startswith("cloud-agent-")) and .state == "Shutdown") | .udid' \
  | while read -r old; do
      echo "Deleting leftover simulator $old"
      sim-remote simctl delete "$old"
    done

runtime="$(sim-remote simctl list runtimes --json \
  | jq -r '[.runtimes[] | select(.platform == "iOS" and .isAvailable)] | sort_by(.version | split(".") | map(tonumber)) | last | .identifier // empty')"

devtype="$(sim-remote simctl list devicetypes --json \
  | jq -r --arg n "$DEVICE_TYPE" '(.devicetypes[] | select(.name == $n) | .identifier) // empty')"

if [ -z "$devtype" ]; then
  devtype="$(sim-remote simctl list devicetypes --json \
    | jq -r '[.devicetypes[] | select(.name | test("^iPhone [0-9]+( Pro)?$")) | {identifier, n: (.name | capture("iPhone (?<n>[0-9]+)").n | tonumber), pro: (.name | endswith("Pro"))}] | sort_by(.n, .pro) | last | .identifier // empty')"
  echo "Device type '$DEVICE_TYPE' is not on this runner. Using $devtype"
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
echo "Simulator $SIM_NAME ($UDID) is booted. It reaches Metro at localhost:8081 and the mock PDS at localhost:3000."
