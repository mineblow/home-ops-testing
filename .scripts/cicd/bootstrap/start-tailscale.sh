#!/usr/bin/env bash
set -euo pipefail

tailscale up \
  --authkey=${TAILSCALE_AUTHKEY:-} \
  --oauth-client-id="$TAILSCALE_CLIENT_ID" \
  --oauth-client-secret="$TAILSCALE_CLIENT_SECRET" \
  --hostname="github-${ENV_NAME:-ci}" \
  --advertise-tags=tag:github-ci \
  --ssh --accept-routes=false
