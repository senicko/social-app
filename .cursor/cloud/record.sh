#!/usr/bin/env bash
# Record the Argent Cloud simulator screen through sim-remote.
#
#   .cursor/cloud/record.sh start <name>   starts recording to media/<name>.mp4
#   .cursor/cloud/record.sh stop           stops it and waits for the download
#
# argent's own screen-recording tool does not support remote simulators, so the
# runbook records with `sim-remote simctl io <UDID> recordVideo`, which runs
# until it receives SIGINT and then downloads the file to the local path.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

PIDFILE=.cursor/cloud/.record.pid
NAMEFILE=.cursor/cloud/.record.name

case "${1:-}" in
  start)
    name="${2:?usage: record.sh start <name>}"
    # shellcheck disable=SC1091
    source .cursor/cloud/session.env
    if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
      echo "A recording is already running (pid $(cat "$PIDFILE")); stop it first." >&2
      exit 1
    fi
    mkdir -p media
    sim-remote simctl io "$SIM_UDID" recordVideo --codec h264 --force "media/$name.mp4" \
      > ".cursor/cloud/.record-$name.log" 2>&1 &
    echo $! > "$PIDFILE"
    echo "$name" > "$NAMEFILE"
    sleep 1
    kill -0 "$(cat "$PIDFILE")" 2>/dev/null || { echo "recordVideo exited immediately:"; cat ".cursor/cloud/.record-$name.log"; exit 1; }
    echo "Recording media/$name.mp4 (pid $(cat "$PIDFILE"))"
    ;;
  stop)
    [ -f "$PIDFILE" ] || { echo "No recording in progress." >&2; exit 1; }
    pid="$(cat "$PIDFILE")"
    name="$(cat "$NAMEFILE" 2>/dev/null || echo recording)"
    kill -INT "$pid" 2>/dev/null || true
    # Not our child in this shell, so poll instead of wait: the download
    # finishes after SIGINT.
    for _ in $(seq 1 120); do
      kill -0 "$pid" 2>/dev/null || break
      sleep 1
    done
    rm -f "$PIDFILE" "$NAMEFILE"
    if [ -s "media/$name.mp4" ]; then
      dur="$(ffprobe -v error -show_entries format=duration -of csv=p=0 "media/$name.mp4" 2>/dev/null || echo unknown)"
      echo "Saved media/$name.mp4 (duration ${dur}s)"
    else
      echo "media/$name.mp4 is missing or empty. recordVideo output:" >&2
      cat ".cursor/cloud/.record-$name.log" >&2 || true
      exit 1
    fi
    ;;
  *)
    echo "usage: $0 start <name> | stop" >&2
    exit 2
    ;;
esac
