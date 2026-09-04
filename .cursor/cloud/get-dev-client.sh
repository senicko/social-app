#!/usr/bin/env bash
# Build the iOS simulator dev client on EAS and download it into build/.
#
#   .cursor/cloud/get-dev-client.sh                 fresh `eas build --profile dev-sim`, wait, download
#   .cursor/cloud/get-dev-client.sh --reuse-latest  download the newest FINISHED dev-sim build instead
#
# BSKY_DEV_CLIENT_URL, when set, skips EAS entirely and downloads that .tar.gz
# (escape hatch for a build made elsewhere).
#
# Needs eas-cli authenticated: the EXPO_TOKEN secret in the cloud, or an
# interactive `eas login` on a laptop. Prints the path of Bluesky.app on the
# last line. A JS-only change does not need a new native build, but the agent
# has no other copy of the app, so it builds one per run unless told to reuse.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

PROFILE="${EAS_PROFILE:-dev-sim}"
OUT=build
TARBALL="$OUT/dev-client.tar.gz"
mkdir -p "$OUT"

# eas prints its non-JSON chatter to stderr in --json mode; keep it in a log.
EAS_LOG="$OUT/eas.log"
: > "$EAS_LOG"

eas_json() { eas "$@" --json --non-interactive 2>>"$EAS_LOG" | sed -n '/^[\[{]/,$p'; }

need_eas() {
  if ! eas whoami >/dev/null 2>&1; then
    echo "eas-cli is not authenticated. Set the EXPO_TOKEN secret (expo.dev > account settings > Access tokens)." >&2
    exit 1
  fi
}

if [ -n "${BSKY_DEV_CLIENT_URL:-}" ]; then
  echo "Downloading dev client from BSKY_DEV_CLIENT_URL (skipping EAS)"
  curl -fsSL "$BSKY_DEV_CLIENT_URL" -o "$TARBALL"
elif [ "${1:-}" = "--reuse-latest" ]; then
  need_eas
  latest="$(eas_json build:list --platform ios --build-profile "$PROFILE" --status finished --limit 1)"
  URL="$(printf '%s' "$latest" | jq -r '.[0].artifacts.buildUrl // empty')"
  ID="$(printf '%s' "$latest" | jq -r '.[0].id // empty')"
  if [ -z "$URL" ]; then
    echo "No finished '$PROFILE' build with an artifact found; run without --reuse-latest to build one." >&2
    exit 1
  fi
  echo "Reusing EAS build $ID (profile $PROFILE, commit $(printf '%s' "$latest" | jq -r '.[0].gitCommitHash // "?"' | cut -c1-9))"
  curl -fsSL "$URL" -o "$TARBALL"
else
  need_eas
  echo "Starting EAS build (profile $PROFILE) for commit $(git rev-parse --short HEAD)"
  started="$(eas_json build --platform ios --profile "$PROFILE" --no-wait)"
  ID="$(printf '%s' "$started" | jq -r 'if type=="array" then .[0].id else .id end')"
  [ -n "$ID" ] && [ "$ID" != "null" ] || { echo "eas build did not return a build id; see $EAS_LOG" >&2; cat "$EAS_LOG" >&2; exit 1; }
  echo "EAS build $ID queued: https://expo.dev/accounts/$(eas_json build:view "$ID" | jq -r '.project.ownerAccount.name // "-"')/projects/$(eas_json build:view "$ID" | jq -r '.project.slug // "-"')/builds/$ID"
  while :; do
    status="$(eas_json build:view "$ID" | jq -r .status)"
    case "$status" in
      FINISHED) break ;;
      ERRORED|CANCELED)
        echo "EAS build $ID $status:" >&2
        eas_json build:view "$ID" | jq '{status, error}' >&2
        exit 1 ;;
      *) echo "  $(date +%H:%M:%S) $status"; sleep 60 ;;
    esac
  done
  URL="$(eas_json build:view "$ID" | jq -r '.artifacts.buildUrl')"
  curl -fsSL "$URL" -o "$TARBALL"
fi

rm -rf "$OUT/Debug-iphonesimulator"
tar -xzf "$TARBALL" -C "$OUT"
APP="$(find "$OUT" -maxdepth 2 -type d -name Bluesky.app | head -1)"
[ -n "$APP" ] || { echo "Bluesky.app not found in the archive" >&2; exit 1; }
python3 - "$APP/Info.plist" <<'PY' 2>/dev/null || true
import plistlib, sys
p = plistlib.load(open(sys.argv[1], 'rb'))
print('version', p.get('CFBundleShortVersionString'), 'build', p.get('CFBundleVersion'))
PY
echo "$APP"
