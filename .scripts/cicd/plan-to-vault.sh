#!/usr/bin/env bash
set -euo pipefail

# === Required ENV Vars ===
: "${ENV_NAME:?Missing ENV_NAME}"
: "${ENV_PATH:?Missing ENV_PATH}"
: "${VAULT_ADDR:?Missing VAULT_ADDR}"
: "${VAULT_TOKEN:?Missing VAULT_TOKEN}"
: "${VAULT_PLAN_PATH:?Missing VAULT_PLAN_PATH}"  # Must be explicit to avoid accidental overwrite

PLAN_FILE="${ENV_PATH}/tfplan"

echo "📦 Running tofu init..."
tofu -chdir="$ENV_PATH" init -backend-config=backend-consul.hcl -reconfigure

echo "🧊 Running tofu plan..."
tofu -chdir="$ENV_PATH" plan -no-color -out=tfplan

if [[ ! -f "$PLAN_FILE" ]]; then
  echo "❌ tfplan not found at $PLAN_FILE"
  exit 1
fi

# Safe base64 encoding
PLAN_B64=$(base64 < "$PLAN_FILE")

# Mask each line (in case multiline leaks later)
echo "$PLAN_B64" | fold -w 64 | while read -r line; do echo "::add-mask::$line"; done

# Upload to Vault
curl -s --request POST "$VAULT_ADDR/v1/$VAULT_PLAN_PATH" \
  --header "X-Vault-Token: $VAULT_TOKEN" \
  --header "Content-Type: application/json" \
  --data "$(printf '{"data":{"plan":"%s"}}' "$PLAN_B64")"

echo "✅ Plan stored at $VAULT_PLAN_PATH"

# Optional: verify decode & format (comment out if not needed)
# echo "$PLAN_B64" | base64 -d | tofu show -
