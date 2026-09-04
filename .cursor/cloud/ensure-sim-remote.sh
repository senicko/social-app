#!/usr/bin/env bash
# Make sure the Argent Cloud client (sim-remote) is on PATH.
#
# Default source: the public GitHub release below, picking the asset for this
# machine's architecture (x86_64 Linux on Cursor VMs; arm64 macOS when run on a
# laptop for testing). The companion `sim-remote-daemon` asset is installed next
# to it when the release has one.
#
# SIM_REMOTE_DOWNLOAD_URL, when set, overrides the default with a single file:
# a raw binary, or a .tar.gz/.zip containing a `sim-remote` executable.
#
# Installs into /usr/local/bin (override with SIM_REMOTE_INSTALL_DIR), where the
# argent tool-server started by the MCP server can see it. Idempotent: exits
# early when a working sim-remote is already installed.
set -euo pipefail

DEFAULT_SIM_REMOTE_RELEASE="https://github.com/software-mansion/sim-remote-releases/releases/download/softu"
INSTALL_DIR="${SIM_REMOTE_INSTALL_DIR:-/usr/local/bin}"

if command -v sim-remote >/dev/null 2>&1 && sim-remote --help >/dev/null 2>&1; then
  echo "sim-remote already installed: $(command -v sim-remote)"
  exit 0
fi

case "$(uname -s)-$(uname -m)" in
  Linux-x86_64)   TRIPLE="x86_64-unknown-linux-gnu" ;;
  Linux-aarch64)  TRIPLE="aarch64-unknown-linux-gnu" ;;
  Darwin-arm64)   TRIPLE="aarch64-apple-darwin" ;;
  *) TRIPLE="" ;;
esac

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

install_bin() {
  # install_bin <source file> <name>
  if [ -w "$INSTALL_DIR" ]; then
    install -m 0755 "$1" "$INSTALL_DIR/$2"
  else
    sudo install -m 0755 "$1" "$INSTALL_DIR/$2"
  fi
}

if [ -n "${SIM_REMOTE_DOWNLOAD_URL:-}" ]; then
  echo "Downloading sim-remote from SIM_REMOTE_DOWNLOAD_URL"
  curl -fsSL "$SIM_REMOTE_DOWNLOAD_URL" -o "$tmp/download"
  case "$SIM_REMOTE_DOWNLOAD_URL" in
    *.tar.gz|*.tgz)
      tar -xzf "$tmp/download" -C "$tmp"
      bin="$(find "$tmp" -type f -name sim-remote | head -1)" ;;
    *.zip)
      unzip -q "$tmp/download" -d "$tmp/unzipped"
      bin="$(find "$tmp/unzipped" -type f -name sim-remote | head -1)" ;;
    *)
      bin="$tmp/download" ;;
  esac
  [ -n "${bin:-}" ] && [ -f "$bin" ] || { echo "No sim-remote executable found in the download" >&2; exit 1; }
  install_bin "$bin" sim-remote
else
  [ -n "$TRIPLE" ] || { echo "Unsupported platform $(uname -s)-$(uname -m); set SIM_REMOTE_DOWNLOAD_URL" >&2; exit 1; }
  echo "Downloading sim-remote ($TRIPLE) from $DEFAULT_SIM_REMOTE_RELEASE"
  curl -fsSL "$DEFAULT_SIM_REMOTE_RELEASE/sim-remote-$TRIPLE" -o "$tmp/sim-remote"
  install_bin "$tmp/sim-remote" sim-remote
  if curl -fsSL "$DEFAULT_SIM_REMOTE_RELEASE/sim-remote-daemon-$TRIPLE" -o "$tmp/sim-remote-daemon" 2>/dev/null; then
    install_bin "$tmp/sim-remote-daemon" sim-remote-daemon
  fi
fi

export PATH="$INSTALL_DIR:$PATH"
sim-remote --help >/dev/null
echo "sim-remote installed at $INSTALL_DIR/sim-remote"
