#!/usr/bin/env bash
# Build the iOS simulator dev client on EAS (profile dev-sim) and unpack it into build/.
#   get-dev-client.sh                 fresh build: eas waits for it (15-25 min), then downloads
#   get-dev-client.sh --reuse-latest  newest finished dev-sim build instead of building
# Needs eas-cli authenticated (EXPO_TOKEN secret). Prints the Bluesky.app path on the last line.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

# Cursor prepends its own /exec-daemon/node (v22) to PATH; prefer the image's Node 24.
export PATH="/usr/bin:$PATH"
eas whoami >/dev/null 2>&1 || { echo "eas-cli is not authenticated; set the EXPO_TOKEN secret" >&2; exit 1; }

if [ "${1:-}" = "--reuse-latest" ]; then
  build="$(eas build:list --json --non-interactive --platform ios --build-profile dev-sim --status finished --limit 1 | jq '.[0]')"
else
  echo "Starting EAS build (dev-sim) for $(git rev-parse --short HEAD); eas waits for it, expect 15-25 minutes"
  build="$(eas build --platform ios --profile dev-sim --json --non-interactive | jq 'if type=="array" then .[0] else . end')"
fi
id="$(printf '%s' "$build" | jq -r '.id // empty')"
url="$(printf '%s' "$build" | jq -r '.artifacts.buildUrl // empty')"
if [ -z "$url" ] && [ -n "$id" ]; then   # eas printed the build before the artifact was attached
  url="$(eas build:view "$id" --json | jq -r '.artifacts.buildUrl // empty')"
fi
[ -n "$url" ] || { echo "no artifact in the EAS response:" >&2; printf '%s\n' "$build" >&2; exit 1; }
echo "EAS build $id"

rm -rf build && mkdir -p build
curl -fsSL "$url" | tar -xz -C build
find build -maxdepth 2 -type d -name Bluesky.app | head -1
