#!/usr/bin/env bash
set -euo pipefail

# Render creates the disk mount after image build. Make the mount root usable
# by Paseo's uid 1000 user without recursively touching existing repositories.
install -d -m 0755 /workspace
chown paseo:paseo /workspace

# Ensure repositories cloned as root are writable by paseo.
if [[ -d /workspace/repos ]]; then
  chown -R paseo:paseo /workspace/repos
fi

# Seed agent configuration once on the persistent disk. Keep later user edits.
install -d -m 0755 -o paseo -g paseo \
  /workspace/.config/opencode \
  /workspace/.pi/agent \
  /workspace/.local/state
if [[ ! -e /workspace/.config/opencode/opencode.json ]]; then
  install -m 0644 -o paseo -g paseo \
    /opt/render-devbox/opencode.json \
    /workspace/.config/opencode/opencode.json
fi
if [[ ! -e /workspace/.pi/agent/models.json ]]; then
  install -m 0644 -o paseo -g paseo \
    /opt/render-devbox/pi-models.json \
    /workspace/.pi/agent/models.json
fi

if [[ -n "${AZURE_API_KEY:-}" ]]; then
  node /opt/render-devbox/azure-foundry-proxy.mjs \
    >>/workspace/.local/state/azure-foundry-proxy.log 2>&1 &
fi

# The managed SSH shell uses root's HOME. Paseo and its agents run as paseo.
export HOME=/home/paseo

# Render's default PORT is 10000. Respect an explicit PASEO_LISTEN override.
if [[ -z "${PASEO_LISTEN:-}" ]]; then
  export PASEO_LISTEN="0.0.0.0:${PORT:-10000}"
fi

# Web services need their public hostname in Paseo's DNS-rebinding allowlist.
# Private services have no public hostname and keep Paseo's safe defaults.
if [[ -z "${PASEO_HOSTNAMES:-}" && -n "${RENDER_EXTERNAL_HOSTNAME:-}" ]]; then
  export PASEO_HOSTNAMES="$RENDER_EXTERNAL_HOSTNAME"
fi

# AWS SDKs commonly use AWS_REGION while the CLI accepts AWS_DEFAULT_REGION.
if [[ -z "${AWS_REGION:-}" && -n "${AWS_DEFAULT_REGION:-}" ]]; then
  export AWS_REGION="$AWS_DEFAULT_REGION"
fi

exec /usr/bin/tini -- /usr/local/bin/paseo-docker-entrypoint
