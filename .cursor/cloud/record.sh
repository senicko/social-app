#!/usr/bin/env bash

# record.sh
#
# Record a remote simulator screen via sim-remote.
# Argent's own recorder does not support remote sims.
# Needs .cursor/cloud/session.env (SIM_UDID) from start.sh.
#
# Commands
#   start <name>   Record to media/<name>.mp4 in the background
#   stop           End recording and wait for the download

set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

# shellcheck disable=SC1091
source .cursor/cloud/session.env

case "${1:-}" in
  start)
    name="${2:?usage: record.sh start <name>}"
    if pgrep -f "^sim-remote simctl io .* recordVideo" >/dev/null; then
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
    pgrep -f "^sim-remote simctl io .* recordVideo" >/dev/null || { echo "recordVideo exited immediately:" >&2; cat .cursor/cloud/record.log >&2; exit 1; }
    echo "recording media/$name.mp4"
    ;;
  stop)
    # Output path is the .mp4 argument on the running recordVideo command.
    pid="$(pgrep -f "^sim-remote simctl io .* recordVideo" | head -1 || true)"
    [ -n "$pid" ] || { echo "no recording is running" >&2; exit 1; }
    file="$(ps -o args= -p "$pid" | tr ' ' '\n' | grep -m1 '\.mp4$' || true)"
    [ -n "$file" ] || { echo "cannot find the output path of recordVideo (pid $pid)" >&2; exit 1; }
    pkill -INT -f "^sim-remote simctl io .* recordVideo"
    for _ in $(seq 60); do pgrep -f "^sim-remote simctl io .* recordVideo" >/dev/null || break; sleep 1; done
    [ -s "$file" ] || { echo "$file is missing or empty. recordVideo output:" >&2; cat .cursor/cloud/record.log >&2; exit 1; }
    echo "saved $file ($(ffprobe -v error -show_entries format=duration -of csv=p=0 "$file" 2>/dev/null || echo '?')s)"
    ;;
  *) echo "usage: $0 start|stop" >&2; exit 2 ;;
esac
