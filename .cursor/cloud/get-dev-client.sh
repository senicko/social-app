#!/usr/bin/env bash

# get-dev-client.sh
#
# Build or download the iOS simulator dev client from EAS.
# Profile is dev-sim. Output lands under build/.
# Prints the Bluesky.app path on the last line.
#
# Commands
#   (default)         Fresh EAS build then download (about 15-25 min)
#   --reuse-latest    Newest finished dev-sim build instead
#
# Required secrets
#   EXPO_TOKEN

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

# Cursor prepends its own Node 22 on PATH. Prefer the image Node 24.
export PATH="/usr/bin:$PATH"
eas whoami >/dev/null 2>&1 || { echo "eas-cli is not authenticated. Set the EXPO_TOKEN secret." >&2; exit 1; }

if [ "${1:-}" = "--reuse-latest" ]; then
  build="$(eas build:list --json --non-interactive --platform ios --build-profile dev-sim --status finished --limit 1 | jq '.[0]')"
else
  echo "Starting EAS build (dev-sim) for $(git rev-parse --short HEAD). eas waits for it. Expect 15-25 minutes."
  build="$(eas build --platform ios --profile dev-sim --json --non-interactive | jq 'if type=="array" then .[0] else . end')"
fi

id="$(printf '%s' "$build" | jq -r '.id // empty')"
url="$(printf '%s' "$build" | jq -r '.artifacts.buildUrl // empty')"

# eas may return the build before the artifact URL is attached.
if [ -z "$url" ] && [ -n "$id" ]; then
  url="$(eas build:view "$id" --json | jq -r '.artifacts.buildUrl // empty')"
fi

[ -n "$url" ] || { echo "no artifact in the EAS response:" >&2; printf '%s\n' "$build" >&2; exit 1; }
echo "EAS build $id"

rm -rf build && mkdir -p build
curl -fsSL "$url" | tar -xz -C build
find build -maxdepth 2 -type d -name Bluesky.app | head -1
