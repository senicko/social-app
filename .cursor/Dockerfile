FROM ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive

# tmux is required for Cursor cloud terminals.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
        ca-certificates curl file git jq sudo tmux ffmpeg \
        postgresql postgresql-client redis-server \
 && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://deb.nodesource.com/setup_24.x | bash - \
 && apt-get install -y --no-install-recommends nodejs \
 && rm -rf /var/lib/apt/lists/* \
 && npm install -g --no-audit --no-fund pnpm@11.21.0 eas-cli@23.2.0 \
 && npm cache clean --force

RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      -o /usr/share/keyrings/githubcli-archive-keyring.gpg \
 && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      > /etc/apt/sources.list.d/github-cli.list \
 && apt-get update \
 && apt-get install -y --no-install-recommends gh \
 && rm -rf /var/lib/apt/lists/*

RUN base=https://github.com/software-mansion/sim-remote-releases/releases/download/softu \
 && curl -fsSL "$base/sim-remote-x86_64-unknown-linux-gnu" -o /usr/local/bin/sim-remote \
 && curl -fsSL "$base/sim-remote-daemon-x86_64-unknown-linux-gnu" -o /usr/local/bin/sim-remote-daemon \
 && chmod 0755 /usr/local/bin/sim-remote /usr/local/bin/sim-remote-daemon \
 && sim-remote --help >/dev/null

# Passwordless sudo for mock-backend.sh Postgres setup.
RUN id -u ubuntu &>/dev/null || useradd -m -s /bin/bash ubuntu
RUN usermod -aG sudo ubuntu
RUN echo "ubuntu ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/ubuntu

USER ubuntu
WORKDIR /home/ubuntu
