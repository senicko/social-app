FROM ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive

# System tools: git/curl for the checkout, ffmpeg + gifsicle for PR media,
# jq for EAS/simctl JSON, build-essential + python3 for any native npm module,
# postgresql + redis-server for the local Bluesky mock network (dev-env).
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates curl git gnupg jq sudo unzip xz-utils tmux openssh-client \
      ffmpeg gifsicle build-essential python3 \
      postgresql postgresql-client redis-server \
 && rm -rf /var/lib/apt/lists/*

# Node 24 (the repo pins 24.19 in .nvmrc / devEngines), pnpm 11.21 (pinned in
# package.json), EAS CLI and GitHub CLI.
RUN curl -fsSL https://deb.nodesource.com/setup_24.x | bash - \
 && apt-get install -y --no-install-recommends nodejs \
 && rm -rf /var/lib/apt/lists/* \
 && npm install -g pnpm@11.21.0 eas-cli \
 && npm cache clean --force

# argent, globally, so the MCP server registered for cloud agents is simply
# `argent mcp` and does not depend on the working directory. The MoQ/WebTransport
# native addon (@fails-components/webtransport-transport-http3-quiche) MUST be
# built: ios-remote screenshot/describe/gesture tools talk to the runner over
# HTTP/3 QUIC, and without webtransport.node every call fails with
# "Opening handshake failed". Do not use --ignore-scripts here. node-pty and
# tree-sitter ship prebuilds; only the quiche transport needs a compile.
RUN npm install -g --no-audit --no-fund @swmansion/argent \
 && node -e "require('@fails-components/webtransport-transport-http3-quiche'); console.log('webtransport ok')" \
 && argent --version

RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      -o /usr/share/keyrings/githubcli-archive-keyring.gpg \
 && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      > /etc/apt/sources.list.d/github-cli.list \
 && apt-get update \
 && apt-get install -y --no-install-recommends gh \
 && rm -rf /var/lib/apt/lists/*

# Cursor runs the agent as a non-root "ubuntu" user with passwordless sudo.
# ubuntu:24.04 already ships that user; the guard keeps this idempotent.
RUN id -u ubuntu >/dev/null 2>&1 || useradd -m -s /bin/bash ubuntu \
 && echo "ubuntu ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/ubuntu \
 && chmod 0440 /etc/sudoers.d/ubuntu

# sim-remote (the Argent Cloud client) is not on a public registry. It is
# installed at build/start time by .cursor/cloud/ensure-sim-remote.sh from the
# SIM_REMOTE_DOWNLOAD_URL secret, into /usr/local/bin so the argent tool-server
# spawned by the MCP server can find it on PATH.

USER ubuntu
WORKDIR /home/ubuntu
