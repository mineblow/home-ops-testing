#!/usr/bin/env bash
set -euo pipefail

# === Required Vars ===
: "${VAULT_ADDR:?Missing VAULT_ADDR}"
: "${VAULT_ROLE:?Missing VAULT_ROLE}"
: "${VAULT_TOKEN_VAR_NAME:=VAULT_TOKEN}"  # Default if not passed

: "${ACTIONS_ID_TOKEN_REQUEST_TOKEN:?Missing GitHub OIDC token}"
: "${ACTIONS_ID_TOKEN_REQUEST_URL:?Missing GitHub OIDC URL}"

# === Get GitHub OIDC JWT ===
JWT=$(curl -s -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" \
            "$ACTIONS_ID_TOKEN_REQUEST_URL" | jq -r .value)

# === Authenticate to Vault ===
RESPONSE=$(curl -s --request POST \
  --data "{\"jwt\":\"$JWT\",\"role\":\"$VAULT_ROLE\"}" \
  "$VAULT_ADDR/v1/auth/jwt/login")

TOKEN=$(echo "$RESPONSE" | jq -r .auth.client_token)

if [[ -z "$TOKEN" || "$TOKEN" == "null" ]]; then
  echo "❌ Vault login failed for role: $VAULT_ROLE"
  echo "$RESPONSE"
  exit 1
fi

# === Export and Mask the Token ===
echo "::add-mask::$TOKEN"
echo "$VAULT_TOKEN_VAR_NAME=$TOKEN" >> "$GITHUB_ENV"
