#!/usr/bin/env bash
set -euo pipefail

# === Required ENV Vars ===
: "${ENV_NAME:?Missing ENV_NAME}"
: "${ENV_PATH:?Missing ENV_PATH}"
: "${VAULT_ADDR:?Missing VAULT_ADDR}"
: "${VAULT_TOKEN:?Missing VAULT_TOKEN}"
: "${VAULT_PLAN_PATH:?Missing VAULT_PLAN_PATH}"  # Format: kv/<path>, not kv/data/...

PLAN_FILE="${ENV_PATH}/tfplan"

echo "📦 Running tofu init..."
tofu -chdir="$ENV_PATH" init -backend-config=backend-consul.hcl -reconfigure

echo "🧊 Running tofu plan..."
tofu -chdir="$ENV_PATH" plan -no-color -out=tfplan

if [[ ! -f "$PLAN_FILE" ]]; then
  echo "❌ tfplan not found at $PLAN_FILE"
  exit 1
fi

echo "📦 Encoding plan file as base64..."
ENCODED=$(base64 -w 0 "$PLAN_FILE")
if [[ -z "$ENCODED" ]]; then
  echo "❌ Base64 encoding failed or produced empty output"
  exit 1
fi

echo "🔐 Uploading encoded plan to Vault at: $VAULT_PLAN_PATH"
vault kv put "$VAULT_PLAN_PATH" plan="$ENCODED" >/dev/null || {
  echo "❌ Vault upload failed"
  exit 1
}

echo "✅ Plan uploaded successfully to Vault: $VAULT_PLAN_PATH"
