#!/usr/bin/env bash

# screenshot.sh
#
# Save a screenshot of the remote simulator to media/<name>.png. sim-remote
# takes it on the runner and downloads it here. Needs SIM_UDID, read from
# .cursor/cloud/session.env (written by start.sh) unless already set.
#
# Usage
#   screenshot.sh <name>    Write media/<name>.png
#
# pr.sh attaches media/before.png and media/after.png.
#
# Env
#   SCREENSHOT_MAX_MB   Size limit (default 10, GitHub Free)

set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

name="${1:?usage: screenshot.sh <name>}"
MAX_MB="${SCREENSHOT_MAX_MB:-20}"

if [ -z "${SIM_UDID:-}" ] && [ -f .cursor/cloud/session.env ]; then
  # shellcheck disable=SC1091
  source .cursor/cloud/session.env
fi
: "${SIM_UDID:?SIM_UDID is missing; run start.sh first}"

mkdir -p media
out="media/$name.png"
rm -f "$out"
sim-remote simctl io "$SIM_UDID" screenshot "$out"

[ -s "$out" ] || { echo "$out is missing or empty" >&2; exit 1; }
type="$(file -b --mime-type "$out")"
[ "$type" = image/png ] || { echo "$out is $type, not a PNG" >&2; exit 1; }
bytes="$(wc -c < "$out" | tr -d ' ')"
if [ "$bytes" -gt $((MAX_MB * 1000 * 1000)) ]; then
  echo "$out is $((bytes / 1000)) kB, over the $MAX_MB MB attachment limit" >&2; exit 1
fi
echo "wrote $out ($((bytes / 1000)) kB)"
