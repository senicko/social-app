#!/usr/bin/env bash

# build-argent.sh
#
# Build argent from software-mansion/argent (main by default) and install it
# globally, so the cloud agent runs the newest tool-server instead of the npm
# release. Runs in the environment install step (snapshot build), after the
# clone, where gh is authenticated through GH_TOKEN: `npm run pack:mcp`
# downloads release assets with `gh release download`, which needs auth even
# for public repos. That is why this is not in the Dockerfile: the image build
# has no secrets. Rebuild the environment to pick up a newer main.
#
# Env
#   ARGENT_REF       Branch, tag or commit to build (default main)
#   ARGENT_SRC       Checkout directory (default $HOME/argent-src)
#   ARGENT_INSTALL   0 stops after packing and prints the tarball path

set -euo pipefail

# Cursor prepends its own Node 22 on PATH. Prefer the image Node 24.
export PATH="/usr/bin:$PATH"

# The install step runs in the repo; the build record goes there (gitignored).
REPO="$PWD"
REF="${ARGENT_REF:-main}"
SRC="${ARGENT_SRC:-$HOME/argent-src}"

gh auth status >/dev/null 2>&1 || { echo "gh is not authenticated. pack:mcp needs GH_TOKEN for its release downloads." >&2; exit 1; }

if [ ! -d "$SRC/.git" ]; then
  git clone --depth 1 https://github.com/software-mansion/argent.git "$SRC"
fi

cd "$SRC"
git fetch --depth 1 origin "$REF"
git checkout -q --detach FETCH_HEAD
sha="$(git rev-parse --short HEAD)"
echo "argent source: $REF at $sha"

# The build never runs Electron; skip its 300 MB binary here.
ELECTRON_SKIP_BINARY_DOWNLOAD=1 npm ci --no-audit --no-fund
rm -f swmansion-argent-*.tgz
npm run pack:mcp
tgz="$(ls -t swmansion-argent-*.tgz | head -1)"
echo "packed $tgz"

if [ "${ARGENT_INSTALL:-1}" = 0 ]; then
  echo "$SRC/$tgz"
  exit 0
fi

# Global, so the MCP command `argent mcp` resolves from PATH in any directory.
# Install scripts must run: they fetch the WebTransport native addon used by
# ios-remote. Without it remote tools fail with "Opening handshake failed".
sudo npm install -g --no-audit --no-fund "./$tgz"
test -f "$(npm root -g)/@swmansion/argent/node_modules/@fails-components/webtransport-transport-http3-quiche/build/Release/webtransport.node"

# main keeps the last release's version number, so record the commit too.
record="argent $(argent --version) from software-mansion/argent $REF at $sha, built $(date -u +%Y-%m-%dT%H:%MZ) from $tgz"
echo "$record"
[ -d "$REPO/.cursor/cloud" ] && echo "$record" > "$REPO/.cursor/cloud/argent-build.log"
