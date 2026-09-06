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
    mkdir -p media
    nohup sim-remote simctl io "$SIM_UDID" recordVideo --codec h264 --force "media/$name.mp4" \
      >.cursor/cloud/record.log 2>&1 &
    echo "recording media/$name.mp4"
    ;;
  stop)
    pkill -INT -f "simctl io .* recordVideo" || { echo "no recording is running" >&2; exit 1; }
    for _ in $(seq 60); do pgrep -f "simctl io .* recordVideo" >/dev/null || break; sleep 1; done
    ls -l media/*.mp4 | tail -1
    ;;
  *) echo "usage: $0 start <name> | stop" >&2; exit 2 ;;
esac
