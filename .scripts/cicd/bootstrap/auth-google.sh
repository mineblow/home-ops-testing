#!/usr/bin/env bash
set -euo pipefail

: "${GOOGLE_APPLICATION_CREDENTIALS:?Missing GOOGLE_APPLICATION_CREDENTIALS environment variable}"

echo "🔐 Activating GCP service account from $GOOGLE_APPLICATION_CREDENTIALS"
RAW=$(gcloud secrets versions access latest --secret=vault_bootstrap)
echo "$RAW" > vault.json

REQUIRED_KEYS=(vault_addr vault_role oauth_client_id oauth_client_secret)
for key in "${REQUIRED_KEYS[@]}"; do
  VALUE=$(jq -r ."$key" vault.json)
  if [[ "$VALUE" == "null" || -z "$VALUE" ]]; then
    echo "❌ Missing $key in vault.json"
    exit 1
  fi
done

export VAULT_ADDR=$(jq -r .vault_addr vault.json)
export VAULT_ROLE=$(jq -r .vault_role vault.json)
export CLIENT_ID=$(jq -r .oauth_client_id vault.json)
export CLIENT_SECRET=$(jq -r .oauth_client_secret vault.json)

echo "::add-mask::$VAULT_ADDR"
echo "::add-mask::$VAULT_ROLE"
echo "::add-mask::$CLIENT_ID"
echo "::add-mask::$CLIENT_SECRET"

echo "VAULT_ADDR=$VAULT_ADDR" >> "$GITHUB_ENV"
echo "VAULT_ROLE=$VAULT_ROLE" >> "$GITHUB_ENV"
echo "TAILSCALE_CLIENT_ID=$CLIENT_ID" >> "$GITHUB_ENV"
echo "TAILSCALE_CLIENT_SECRET=$CLIENT_SECRET" >> "$GITHUB_ENV"
