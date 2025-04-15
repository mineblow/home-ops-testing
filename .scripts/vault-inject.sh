#!/usr/bin/env bash
set -euo pipefail
: "${VAULT_ADDR:?Missing VAULT_ADDR environment variable}"
: "${VAULT_TOKEN:?Missing VAULT_TOKEN environment variable}"

ENV_DIR="$(basename "$(pwd)")"  # e.g. "k3s-master", "bootstrap-runner"
TMP_FILE="vault.auto.tfvars"
BACKEND_FILE="backend-consul.hcl"

echo "📁 Working in environment: $ENV_DIR"
echo "🔍 VAULT_ADDR=$VAULT_ADDR"
echo "🔐 VAULT_TOKEN length: ${#VAULT_TOKEN}"

> "$TMP_FILE"
> "$BACKEND_FILE"

trap 'rm -f "$BACKEND_FILE"' EXIT  # Auto-clean backend file

### 🔐 Proxmox Terraform API vars
BASE_PATH="kv/data/home-ops/proxmox"
declare -A SECRETS=(
  ["proxmox_api_url"]="api_url"
  ["proxmox_api_token"]="automation_full_token"
)

for VAR in "${!SECRETS[@]}"; do
  KEY="${SECRETS[$VAR]}"
  VAL=$(curl -s -H "X-Vault-Token: $VAULT_TOKEN" \
    "$VAULT_ADDR/v1/${BASE_PATH}/${KEY}" \
    | jq -r '.data.data.value // empty')

  if [[ -z "$VAL" || "$VAL" == "null" ]]; then
    echo "❌ Missing secret: $KEY"
    exit 1
  fi

  echo "$VAR = \"$VAL\"" >> "$TMP_FILE"
done

### 🔐 Consul backend secrets
ENV_PATH="kv/data/home-ops/opentofu/homelab/$ENV_DIR"

LOCK_PATH=$(curl -s -H "X-Vault-Token: $VAULT_TOKEN" \
  "$VAULT_ADDR/v1/$ENV_PATH/consul/state_locking_path" \
  | jq -r '.data.data.value // empty')

LOCK_TOKEN=$(curl -s -H "X-Vault-Token: $VAULT_TOKEN" \
  "$VAULT_ADDR/v1/$ENV_PATH/consul/state_locking_token" \
  | jq -r '.data.data.value // empty')

CONSUL_DOMAIN=$(curl -s -H "X-Vault-Token: $VAULT_TOKEN" \
  "$VAULT_ADDR/v1/kv/data/home-ops/consul/domain" \
  | jq -r '.data.data.value // empty' | sed 's:/*$::')

if [[ -z "$LOCK_PATH" || -z "$LOCK_TOKEN" || -z "$CONSUL_DOMAIN" ]]; then
  echo "❌ Missing Consul config for $ENV_DIR"
  exit 1
fi

cat <<EOF > "$BACKEND_FILE"
address = "$CONSUL_DOMAIN"
path    = "$LOCK_PATH"
EOF

export CONSUL_HTTP_ADDR="$CONSUL_DOMAIN"
export CONSUL_HTTP_TOKEN="$LOCK_TOKEN"
export TOFU_LOG="warn"

echo "✅ backend-consul.hcl written with:"
echo "  - address: $CONSUL_DOMAIN"
echo "  - path:    $LOCK_PATH"

### 🔐 Proxmox SSH key
SSH_KEY=$(curl -s -H "X-Vault-Token: $VAULT_TOKEN" \
  "$VAULT_ADDR/v1/kv/data/home-ops/proxmox/automation_ssh_key" \
  | jq -r '.data.data.value // empty')

if [[ -z "$SSH_KEY" || "$SSH_KEY" == "null" ]]; then
  echo "❌ Missing SSH key"
  exit 1
fi

TMP_SSH_KEY=$(mktemp)
echo "$SSH_KEY" > "$TMP_SSH_KEY"
chmod 600 "$TMP_SSH_KEY"
eval "$(ssh-agent -s)" > /dev/null
ssh-add "$TMP_SSH_KEY"

echo "proxmox_ssh_user = \"auto\"" >> "$TMP_FILE"
echo "proxmox_ssh_private_key = \"$TMP_SSH_KEY\"" >> "$TMP_FILE"

echo "✅ SSH + vars ready in $TMP_FILE"
echo "🚀 Run this next:"
echo "   tofu init -backend-config=backend-consul.hcl -reconfigure"
