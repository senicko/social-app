# Base image for Cursor cloud agents (docs/cloud-agent-plan.md). Cursor clones the
# repository after this image is built, so nothing from the repo is copied in.
FROM ubuntu:24.04
ARG DEBIAN_FRONTEND=noninteractive

# git/curl for the checkout, jq for EAS and simctl JSON, ffmpeg for PR videos,
# build tools for any native npm module, PostgreSQL + Redis for the dev-env
# mock Bluesky network, tmux for Cursor's terminals.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates curl git jq sudo tmux ffmpeg build-essential python3 \
      postgresql postgresql-client redis-server \
 && rm -rf /var/lib/apt/lists/*

# Node 24 (repo pins 24.19 in .nvmrc), pnpm 11.21 (pinned in package.json), EAS CLI.
RUN curl -fsSL https://deb.nodesource.com/setup_24.x | bash - \
 && apt-get install -y --no-install-recommends nodejs \
 && rm -rf /var/lib/apt/lists/* \
 && npm install -g --no-audit --no-fund pnpm@11.21.0 eas-cli \
 && npm cache clean --force

# argent, globally, so the MCP server registered in Cursor is just `argent mcp`.
# --ignore-scripts skips node-gyp for optional native deps (node-pty ships a
# prebuilt binary, tree-sitter has linux-x64 prebuilds).
RUN npm install -g --ignore-scripts --no-audit --no-fund @swmansion/argent \
 && argent --version

# GitHub CLI 2.99+ (needed for `gh pr create --attach`).
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      -o /usr/share/keyrings/githubcli-archive-keyring.gpg \
 && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      > /etc/apt/sources.list.d/github-cli.list \
 && apt-get update \
 && apt-get install -y --no-install-recommends gh \
 && rm -rf /var/lib/apt/lists/*

# sim-remote, the Argent Cloud client (public release; the daemon asset is the
# same binary under the name the CLI spawns).
RUN case "$(uname -m)" in \
      x86_64)  t=x86_64-unknown-linux-gnu ;; \
      aarch64) t=aarch64-unknown-linux-gnu ;; \
      *) echo "unsupported architecture: $(uname -m)" >&2; exit 1 ;; \
    esac \
 && base=https://github.com/software-mansion/sim-remote-releases/releases/download/softu \
 && curl -fsSL "$base/sim-remote-$t" -o /usr/local/bin/sim-remote \
 && curl -fsSL "$base/sim-remote-daemon-$t" -o /usr/local/bin/sim-remote-daemon \
 && chmod 0755 /usr/local/bin/sim-remote /usr/local/bin/sim-remote-daemon \
 && sim-remote --help >/dev/null

# Cursor runs the agent as a non-root "ubuntu" user with passwordless sudo
# (mock-backend.sh needs sudo for the Postgres cluster).
RUN id -u ubuntu >/dev/null 2>&1 || useradd -m -s /bin/bash ubuntu \
 && echo "ubuntu ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/ubuntu \
 && chmod 0440 /etc/sudoers.d/ubuntu
USER ubuntu
WORKDIR /home/ubuntu
