#!/usr/bin/env bash
set -euo pipefail

# === Required ENV Vars ===
: "${ENV_NAME:?Missing ENV_NAME}"
: "${ENV_PATH:?Missing ENV_PATH}"
: "${VAULT_ADDR:?Missing VAULT_ADDR}"
: "${VAULT_TOKEN:?Missing VAULT_TOKEN}"
: "${VAULT_PLAN_PATH:?Missing VAULT_PLAN_PATH}"  # Format: kv/<path>, not kv/data/...

# Relative to $ENV_PATH since we're using -chdir
PLAN_FILE="tfplan"
PLAN_FULL_PATH="${ENV_PATH}/${PLAN_FILE}"

echo "📦 Running tofu init..."
tofu -chdir="$ENV_PATH" init -backend-config=backend-consul.hcl -reconfigure

echo "🧊 Running tofu plan..."
tofu -chdir="$ENV_PATH" plan -no-color -out="$PLAN_FILE" > /dev/null

if [[ ! -s "$PLAN_FULL_PATH" ]]; then
  echo "❌ tfplan not found or empty at $PLAN_FULL_PATH"
  exit 1
fi

echo "📦 Encoding plan file as base64..."
ENCODED=$(base64 -w 0 "$PLAN_FULL_PATH" || true)
if [[ -z "${ENCODED:-}" ]]; then
  echo "❌ Base64 encoding failed or returned empty output"
  exit 1
fi

echo "🔐 Uploading encoded plan to Vault at: $VAULT_PLAN_PATH"
if ! vault kv put "$VAULT_PLAN_PATH" plan="$ENCODED" >/dev/null; then
  echo "❌ Vault upload failed"
  exit 1
fi

echo "✅ Plan uploaded successfully to Vault: $VAULT_PLAN_PATH"
