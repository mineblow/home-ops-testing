#!/usr/bin/env bash
set -euo pipefail

# Required ENV vars
: "${VAULT_ADDR:?Missing VAULT_ADDR}"
: "${VAULT_TOKEN:?Missing VAULT_TOKEN}"
: "${GITHUB_REPO:?Missing GITHUB_REPO (e.g. mineblow/home-ops)}"
: "${GITHUB_PAT_VAULT_PATH:?Missing Vault path to PAT (e.g. kv/home-ops/github/pat)}"
: "${VAULT_TOKEN_PATH:?Where to store token (e.g. kv/home-ops/github/runner-token)}"

# 1. Pull GitHub PAT from Vault
GITHUB_PAT=$(vault kv get -field=value "$GITHUB_PAT_VAULT_PATH")

# 2. Fetch registration token from GitHub
TOKEN=$(curl -s -X POST \
  -H "Authorization: token $GITHUB_PAT" \
  "https://api.github.com/repos/${GITHUB_REPO}/actions/runners/registration-token" |
  jq -r .token)

if [[ -z "$TOKEN" || "$TOKEN" == "null" ]]; then
  echo "❌ Failed to get GitHub runner token"
  exit 1
fi

# 3. Store in Vault
vault kv put "$VAULT_TOKEN_PATH" value="$TOKEN"
echo "✅ Stored runner token in Vault at $VAULT_TOKEN_PATH"
