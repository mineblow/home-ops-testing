#!/usr/bin/env bash
set -euo pipefail

echo "💥 STARTING ULTRA DEBUG MODE"
set -x  # echo every command

# === Required ENV Vars ===
: "${ENV_NAME:?Missing ENV_NAME}"
: "${ENV_PATH:?Missing ENV_PATH}"
: "${VAULT_ADDR:?Missing VAULT_ADDR}"
: "${VAULT_TOKEN:?Missing VAULT_TOKEN}"
: "${VAULT_PLAN_PATH:?Missing VAULT_PLAN_PATH}"  # Format: kv/<path>, not kv/data/...

PLAN_FILE="${ENV_PATH}/tfplan"

echo "📦 ENVIRONMENT VARIABLES"
env | sort

echo "📍 PWD + whoami"
pwd
whoami
id

echo "🧼 Checking $ENV_PATH"
ls -lahR "$ENV_PATH" || true
stat "$ENV_PATH" || true
df -h "$ENV_PATH" || true
mount | grep "$(dirname "$ENV_PATH")" || true

echo "🚨 Checking if $PLAN_FILE already exists"
if [[ -L "$PLAN_FILE" ]]; then
  echo "⚠️ $PLAN_FILE is a symlink – removing"
  ls -lah "$PLAN_FILE" || true
  rm -f "$PLAN_FILE"
elif [[ -d "$PLAN_FILE" ]]; then
  echo "❌ $PLAN_FILE is a directory – removing"
  ls -lah "$PLAN_FILE" || true
  rm -rf "$PLAN_FILE"
elif [[ -f "$PLAN_FILE" ]]; then
  echo "🧹 $PLAN_FILE is a file – removing"
  ls -lah "$PLAN_FILE"
  rm -f "$PLAN_FILE"
elif [[ -e "$PLAN_FILE" ]]; then
  echo "❗ $PLAN_FILE exists but unknown type – nuking"
  stat "$PLAN_FILE" || true
  rm -rf "$PLAN_FILE"
else
  echo "✅ $PLAN_FILE does not exist – clean slate"
fi

echo "📦 Running tofu init..."
tofu -chdir="$ENV_PATH" init -backend-config=backend-consul.hcl -reconfigure || {
  echo "❌ INIT FAILED"
  exit 1
}

echo "🧊 Running tofu plan..."
tofu -chdir="$ENV_PATH" plan -no-color -out="$PLAN_FILE" || {
  echo "❌ PLAN FAILED"
  echo "🧪 Rechecking directory contents..."
  ls -lahR "$ENV_PATH" || true
  stat "$PLAN_FILE" || true
  mount | grep "$(dirname "$PLAN_FILE")" || true
  df -h . || true
  exit 1
}

echo "📂 Final contents of $ENV_PATH"
ls -lahR "$ENV_PATH"

echo "🧪 Verifying plan file..."
file "$PLAN_FILE" || true
stat "$PLAN_FILE" || true
ls -l "$PLAN_FILE" || true

if [[ ! -s "$PLAN_FILE" ]]; then
  echo "❌ tfplan not found or empty at $PLAN_FILE"
  exit 1
fi

echo "📦 Encoding plan file as base64..."
ENCODED=$(base64 -w 0 "$PLAN_FILE" || true)
if [[ -z "${ENCODED:-}" ]]; then
  echo "❌ Base64 encoding failed"
  file "$PLAN_FILE" || true
  exit 1
fi

echo "🔐 Uploading encoded plan to Vault at: $VAULT_PLAN_PATH"
vault kv put "$VAULT_PLAN_PATH" plan="$ENCODED" || {
  echo "❌ Vault upload failed"
  exit 1
}

echo "✅ SUCCESS: Plan uploaded to Vault"
