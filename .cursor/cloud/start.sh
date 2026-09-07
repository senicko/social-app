#!/usr/bin/env bash

# start.sh
#
# Runs once at the start of every Cursor cloud agent run.
# Starts before the Metro terminal.
#
# What it does
#   1. Install CURSOR-CLOUD.md as an always-on Cursor rule (gitignored)
#   2. Start and seed the mock Bluesky network
#   3. Log in to Argent Cloud, queueing for a runner while the fleet is full
#   4. Pick a simulator that is already booted on that runner
#   5. Tunnel Metro (8081) and mock PDS (3000) into it
#   6. Write .cursor/cloud/session.env for the agent
#
# Every login is a fresh session and logout clears it, so nothing is created,
# erased or deleted here. The runners keep simulators booted; using one is
# much faster than creating our own.
#
# Required secrets
#   SIM_ROUTER_USERNAME
#   SIM_ROUTER_API_KEY
#
# Argent MCP for cloud agents: register `argent mcp` as a stdio server in the
# Cursor dashboard; cloud agents ignore the repo's .cursor/mcp.json.
#
# Optional env
#   SIM_DEVICE_TYPE     Preferred simulator name (default iPhone 17 Pro)
#   SIM_LOGIN_TIMEOUT   Seconds to wait in the queue for a runner (default 900)

set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

# Cursor prepends its own Node 22 on PATH. Prefer the image Node 24.
export PATH="/usr/bin:$PATH"

# Cloud instructions: CURSOR-CLOUD.md becomes an always-on Cursor rule.
# Generated here and gitignored, so nothing about the cloud lives in a local
# checkout. First, so the agent has it even if a later step fails.
mkdir -p .cursor/rules
{ printf -- '---\nalwaysApply: true\n---\n\n'; cat .cursor/cloud/CURSOR-CLOUD.md; } > .cursor/rules/cloud-session.mdc

: "${SIM_ROUTER_USERNAME:?SIM_ROUTER_USERNAME is missing}"
: "${SIM_ROUTER_API_KEY:?SIM_ROUTER_API_KEY is missing}"

DEVICE_TYPE="${SIM_DEVICE_TYPE:-iPhone 17 Pro}"

bash .cursor/cloud/mock-backend.sh start

# Sessions are limited; login waits in the queue when all are taken.
sim-remote login --timeout "${SIM_LOGIN_TIMEOUT:-900}"

devices="$(sim-remote simctl list devices --json)"

# Prints "<udid>\t<name>" of the best device in state $1, or nothing.
# Order: the preferred name, any iPhone Pro, any iPhone, anything.
pick() {
  printf '%s' "$devices" | jq -r --arg n "$DEVICE_TYPE" --arg s "$1" '
    [.devices[][] | select(.isAvailable and .state == $s)]
    | (map(select(.name == $n))
       + map(select(.name | test("^iPhone [0-9]+ Pro$")))
       + map(select(.name | test("^iPhone")))
       + .)
    | .[0] // empty | "\(.udid)\t\(.name)"'
}

read -r UDID SIM_NAME < <(pick Booted) || true

if [ -z "${UDID:-}" ]; then
  # Not expected: the runners keep simulators booted. Boot one rather than fail.
  read -r UDID SIM_NAME < <(pick Shutdown) || true
  [ -n "${UDID:-}" ] || { echo "No available simulator on the leased runner" >&2; sim-remote logout; exit 1; }
  echo "No booted simulator on the runner. Booting $SIM_NAME ($UDID)"
  sim-remote simctl boot "$UDID"
  sim-remote simctl bootstatus "$UDID" -b
fi

for port in 8081 3000; do
  sim-remote reverse start "$UDID" "$port"
done

sim-remote reverse status
{ echo "SIM_UDID=$UDID"; echo "SIM_NAME=$SIM_NAME"; cat .cursor/cloud/mock.env; } > .cursor/cloud/session.env
echo "Simulator $SIM_NAME ($UDID) is ready. It reaches Metro at localhost:8081 and the mock PDS at localhost:3000."
