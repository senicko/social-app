#!/usr/bin/env bash
# Metro dev server for the "metro" terminal of the Cursor cloud environment.
#
# Calls expo's CLI entry directly: `npx expo` refuses to run when the Node
# major differs from devEngines, and pnpm's script wrapper has been seen to
# hang after its pre-run install. CI=1 keeps expo start non-interactive inside
# tmux.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
export CI=1
exec node_modules/expo/bin/cli start --dev-client --port "${METRO_PORT:-8081}"
