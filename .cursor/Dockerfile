FROM ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive

# Install basic dependencies

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
        ca-certificates curl git jq sudo tmux ffmpeg \
        postgresql postgresql-client redis-server \
 && rm -rf /var/lib/apt/lists/*

# Node 24 (social-app pins it),
# pnpm 11.21 (pinned in package.json),
# EAS CLI.

RUN curl -fsSL https://deb.nodesource.com/setup_24.x | bash - \
 && apt-get install -y --no-install-recommends nodejs \
 && rm -rf /var/lib/apt/lists/* \
 && npm install -g --no-audit --no-fund pnpm@11.21.0 eas-cli \
 && npm cache clean --force

# Install Argent

# Install scripts must run: argent's ios-remote tools talk to the Argent Cloud
# runner over HTTP/3, through the @fails-components/webtransport-transport-http3-quiche
# addon, whose install script downloads the prebuilt webtransport.node. Without
# it every screenshot/describe/tap on a remote simulator fails with
# "Opening handshake failed" (found by a cloud agent run). npm 11 warns about
# global install scripts but runs them.
RUN npm install -g --no-audit --no-fund @swmansion/argent \
 && test -f "$(npm root -g)/@swmansion/argent/node_modules/@fails-components/webtransport-transport-http3-quiche/build/Release/webtransport.node" \
 && argent --version

# Install GitHub CLI

RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      -o /usr/share/keyrings/githubcli-archive-keyring.gpg \
 && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      > /etc/apt/sources.list.d/github-cli.list \
 && apt-get update \
 && apt-get install -y --no-install-recommends gh \
 && rm -rf /var/lib/apt/lists/*

# Install sim-remote

RUN base=https://github.com/software-mansion/sim-remote-releases/releases/download/softu \
 && curl -fsSL "$base/sim-remote-x86_64-unknown-linux-gnu" -o /usr/local/bin/sim-remote \
 && curl -fsSL "$base/sim-remote-daemon-x86_64-unknown-linux-gnu" -o /usr/local/bin/sim-remote-daemon \
 && chmod 0755 /usr/local/bin/sim-remote /usr/local/bin/sim-remote-daemon \
 && sim-remote --help >/dev/null

# Config ubuntu user

# Create non-root user (only if it doesn't exist)
RUN id -u ubuntu &>/dev/null || useradd -m -s /bin/bash ubuntu
RUN usermod -aG sudo ubuntu
# Configure passwordless sudo for ubuntu user
RUN echo "ubuntu ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/ubuntu
# Set a password for ubuntu user
RUN echo "ubuntu:ubuntu" | chpasswd

USER ubuntu
WORKDIR /home/ubuntu
