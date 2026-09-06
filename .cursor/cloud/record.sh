#!/usr/bin/env bash

# Record the cloud simulator screen (argent's recorder does not support remote
# simulators). recordVideo runs until SIGINT, then sim-remote downloads the file.
#   record.sh start <name>   records to media/<name>.mp4 in the background
#   record.sh stop           stops the recording and waits for the download

set -euo pipefail

cd "$(git rev-parse --show-toplevel)"
# shellcheck disable=SC1091
source .cursor/cloud/session.env

case "${1:-}" in
  start)
    name="${2:?usage: record.sh start <name>}"
    if pgrep -f "simctl io .* recordVideo" >/dev/null; then
      echo "a recording is already running; stop it first" >&2; exit 1
    fi
    mkdir -p media
    # sim-remote implements recordVideo itself and rejects --codec.
    # set -m: a background job of a non-interactive shell would otherwise start
    # with SIGINT ignored, and `stop` relies on SIGINT to end the recording.
    set -m
    nohup sim-remote simctl io "$SIM_UDID" recordVideo --force "media/$name.mp4" \
      >.cursor/cloud/record.log 2>&1 &
    set +m
    sleep 2
    # Catch an immediate failure (bad flag, no session) instead of finding out at stop.
    pgrep -f "simctl io .* recordVideo" >/dev/null || { echo "recordVideo exited immediately:" >&2; cat .cursor/cloud/record.log >&2; exit 1; }
    echo "recording media/$name.mp4"
    ;;
  stop)
    # The output path is the .mp4 argument of the running recordVideo command.
    pid="$(pgrep -f "simctl io .* recordVideo" | head -1 || true)"
    file="$([ -n "$pid" ] && ps -o args= -p "$pid" | tr ' ' '\n' | grep -m1 '\.mp4$')"
    [ -n "$file" ] || { echo "no recording is running" >&2; exit 1; }
    pkill -INT -f "simctl io .* recordVideo"
    for _ in $(seq 60); do pgrep -f "simctl io .* recordVideo" >/dev/null || break; sleep 1; done
    [ -s "$file" ] || { echo "$file is missing or empty; recordVideo output:" >&2; cat .cursor/cloud/record.log >&2; exit 1; }
    echo "saved $file ($(ffprobe -v error -show_entries format=duration -of csv=p=0 "$file" 2>/dev/null || echo '?')s)"
    ;;
  *) echo "usage: $0 start <name> | stop" >&2; exit 2 ;;
esac
