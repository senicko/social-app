#!/usr/bin/env bash

# record.sh
#
# Record a remote simulator screen via sim-remote.
# Argent's own recorder does not support remote sims.
# start needs .cursor/cloud/session.env (SIM_UDID) from start.sh.
#
# Commands
#   start <name>    Record to media/<name>.mp4 in the background
#   stop            End recording, wait for the download, then encode
#   encode <name>   Write media/<name>-720p.mp4 (H.264, under the attachment limit)
#
# stop encodes on its own so the PR-ready file exists as soon as the
# recording does. Only the -720p file is attached to a PR (see pr.sh).
#
# Env
#   RECORD_MAX_MB     Size limit for the 720p file (default 10, GitHub Free)
#   RECORD_WARN_SECS  Warn when a recording is longer than this (default 30)

set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

MAX_MB="${RECORD_MAX_MB:-10}"
WARN_SECS="${RECORD_WARN_SECS:-30}"
PATTERN='^sim-remote simctl io .* recordVideo'

duration() {
  ffprobe -v error -show_entries format=duration -of csv=p=0 "$1" 2>/dev/null || echo 0
}

encode() {
  local name="$1" src out crf bytes limit
  src="media/$name.mp4"
  out="media/$name-720p.mp4"
  [ -s "$src" ] || { echo "$src is missing or empty" >&2; exit 1; }
  limit=$((MAX_MB * 1000 * 1000))
  # crf 28 first. If that is still over the limit, one more pass at crf 33.
  for crf in 28 33; do
    ffmpeg -y -loglevel error -i "$src" -vf "scale=-2:720" -c:v libx264 -preset veryfast \
      -crf "$crf" -pix_fmt yuv420p -movflags +faststart -an "$out"
    bytes="$(wc -c < "$out" | tr -d ' ')"
    [ "$bytes" -gt "$limit" ] || break
  done
  if [ "$bytes" -gt "$limit" ]; then
    echo "$out is $((bytes / 1000)) kB, over the $MAX_MB MB attachment limit even at crf $crf. Shorten the flow and record again." >&2
    exit 1
  fi
  echo "wrote $out ($((bytes / 1000)) kB, crf $crf)"
}

case "${1:-}" in
  start)
    name="${2:?usage: record.sh start <name>}"
    # shellcheck disable=SC1091
    source .cursor/cloud/session.env
    if pgrep -f "$PATTERN" >/dev/null; then
      echo "a recording is already running. Stop it first." >&2; exit 1
    fi
    mkdir -p media
    # sim-remote implements recordVideo and rejects --codec.
    # set -m so the background job can receive SIGINT from stop.
    set -m
    nohup sim-remote simctl io "$SIM_UDID" recordVideo --force "media/$name.mp4" \
      >.cursor/cloud/record.log 2>&1 &
    set +m
    sleep 2
    # Fail fast if recordVideo exits immediately.
    pgrep -f "$PATTERN" >/dev/null || { echo "recordVideo exited immediately:" >&2; cat .cursor/cloud/record.log >&2; exit 1; }
    echo "recording media/$name.mp4"
    ;;
  stop)
    # Output path is the .mp4 argument on the running recordVideo command.
    pid="$(pgrep -f "$PATTERN" | head -1 || true)"
    [ -n "$pid" ] || { echo "no recording is running" >&2; exit 1; }
    file="$(ps -o args= -p "$pid" | tr ' ' '\n' | grep -m1 '\.mp4$' || true)"
    [ -n "$file" ] || { echo "cannot find the output path of recordVideo (pid $pid)" >&2; exit 1; }
    pkill -INT -f "$PATTERN"
    for _ in $(seq 60); do pgrep -f "$PATTERN" >/dev/null || break; sleep 1; done
    [ -s "$file" ] || { echo "$file is missing or empty. recordVideo output:" >&2; cat .cursor/cloud/record.log >&2; exit 1; }
    secs="$(duration "$file")"
    echo "saved $file (${secs}s)"
    if [ "${secs%.*}" -gt "$WARN_SECS" ] 2>/dev/null; then
      echo "warning: $file is longer than $WARN_SECS s. Keep flows short; long clips hit the attachment limit and slow the PR." >&2
    fi
    encode "$(basename "$file" .mp4)"
    ;;
  encode)
    encode "${2:?usage: record.sh encode <name>}"
    ;;
  *) echo "usage: $0 start <name>|stop|encode <name>" >&2; exit 2 ;;
esac
