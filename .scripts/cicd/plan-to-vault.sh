#!/usr/bin/env bash
set -euo pipefail

# === Required ENV Vars ===
: "${ENV_NAME:?Missing ENV_NAME}"
: "${ENV_PATH:?Missing ENV_PATH}"
: "${VAULT_ADDR:?Missing VAULT_ADDR}"
: "${VAULT_TOKEN:?Missing VAULT_TOKEN}"
: "${VAULT_PLAN_PATH:?Missing VAULT_PLAN_PATH}"  # Must be KV v2 path *without* /data/ prefix

PLAN_FILE="$ENV_PATH/tfplan"

echo "📦 tofu init"
tofu -chdir="$ENV_PATH" init -backend-config=backend-consul.hcl > /dev/null

echo "🧊 tofu plan"
tofu -chdir="$ENV_PATH" plan -out=tfplan > /dev/null

if [[ ! -f "$PLAN_FILE" ]]; then
  echo "❌ tfplan not found at $PLAN_FILE"
  exit 1
fi

echo "🔐 vault kv put plan -> $VAULT_PLAN_PATH"
vault kv put "$VAULT_PLAN_PATH" plan=@"$PLAN_FILE" > /dev/null

echo "✅ Plan uploaded successfully to Vault: $VAULT_PLAN_PATH"
