# syntax=docker/dockerfile:1
FROM ghcr.io/getpaseo/paseo:latest

# Keep the image root-capable for Render's managed SSH shell. The Paseo base
# entrypoint drops the daemon and launched agents to uid/gid 1000 (paseo).
USER root

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
      awscli \
      ca-certificates \
      gh \
      gnupg \
      jq \
      ripgrep; \
    install -d -m 0755 /etc/apt/keyrings; \
    curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg \
      | gpg --dearmor --yes -o /etc/apt/keyrings/cloud.google.gpg; \
    printf '%s\n' \
      'deb [signed-by=/etc/apt/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main' \
      > /etc/apt/sources.list.d/google-cloud-sdk.list; \
    apt-get update; \
    apt-get install -y --no-install-recommends google-cloud-cli; \
    rm -rf /var/lib/apt/lists/*

RUN npm install -g \
      opencode-ai@latest \
      @earendil-works/pi-coding-agent@latest

# Required by Render's Docker SSH integration. The disk is mounted at
# /workspace, not at $HOME, so Render can still provide its SSH shell.
# Render's managed SSH proxy authenticates the container's root account.
# Debian-based images commonly ship root locked, which makes SSH close after
# public-key authentication succeeds.
RUN usermod --unlock root \
    && passwd -d root \
    && usermod --shell /bin/bash paseo \
    && install -d -m 0700 -o paseo -g paseo /home/paseo/.ssh \
    && install -d -m 0700 /root/.ssh

# Keep the image environment consistent with the root account for Render's
# managed SSH shell. The entrypoint switches HOME to /home/paseo for Paseo.
ENV HOME=/root \
    PASEO_HOME=/workspace/.paseo \
    PASEO_LISTEN= \
    PASEO_WEB_UI_ENABLED=true \
    CLAUDE_CONFIG_DIR=/workspace/.claude \
    CODEX_HOME=/workspace/.codex \
    PI_CODING_AGENT_DIR=/workspace/.pi/agent \
    PI_CODING_AGENT_SESSION_DIR=/workspace/.pi/sessions \
    XDG_CONFIG_HOME=/workspace/.config \
    XDG_DATA_HOME=/workspace/.local/share \
    XDG_STATE_HOME=/workspace/.local/state \
    XDG_CACHE_HOME=/workspace/.cache \
    GH_CONFIG_DIR=/workspace/.config/gh \
    CLOUDSDK_CONFIG=/workspace/.config/gcloud \
    AWS_CONFIG_FILE=/workspace/.aws/config \
    AWS_SHARED_CREDENTIALS_FILE=/workspace/.aws/credentials \
    AWS_SDK_LOAD_CONFIG=1 \
    GIT_CONFIG_GLOBAL=/workspace/.gitconfig

WORKDIR /workspace
COPY render-entrypoint.sh /usr/local/bin/render-entrypoint
RUN chmod 0755 /usr/local/bin/render-entrypoint

# Render performs the HTTP health check itself. The base image health check
# assumes port 6767, while Render supplies PORT at runtime.
HEALTHCHECK NONE
EXPOSE 10000
ENTRYPOINT ["/usr/local/bin/render-entrypoint"]
