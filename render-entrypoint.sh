#!/usr/bin/env bash
set -euo pipefail

# Render creates the disk mount after image build. Make the mount root usable
# by Paseo's uid 1000 user without recursively touching existing repositories.
install -d -m 0755 /workspace
chown paseo:paseo /workspace

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
