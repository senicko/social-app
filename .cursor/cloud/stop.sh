#!/usr/bin/env bash
# Release the Argent Cloud runner and stop the local mock network. Run at the
# end of every agent run, also on failure: a leased machine is one nobody else
# can use.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

if [ -f .cursor/cloud/.record.pid ]; then
  bash .cursor/cloud/record.sh stop || true
fi

if [ -f .cursor/cloud/session.env ]; then
  # shellcheck disable=SC1091
  source .cursor/cloud/session.env
  if [ -n "${SIM_UDID:-}" ]; then
    sim-remote reverse stop "$SIM_UDID" "${METRO_PORT:-8081}" || true
    sim-remote reverse stop "$SIM_UDID" "${PDS_PORT:-3000}" || true
    sim-remote simctl shutdown "$SIM_UDID" || true
  fi
fi

sim-remote logout || true
bash .cursor/cloud/mock-backend.sh stop || true
rm -f .cursor/cloud/session.env
echo "Argent Cloud session released."
