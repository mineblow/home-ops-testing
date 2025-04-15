#!/usr/bin/env bash
set -euo pipefail

: "${VAULT_TOKEN:?Missing VAULT_TOKEN}"
: "${VAULT_ADDR:?Missing VAULT_ADDR}"
: "${CONSUL_HTTP_ADDR:?Missing CONSUL_HTTP_ADDR}"
: "${CONSUL_HTTP_TOKEN:?Missing CONSUL_HTTP_TOKEN}"

ENV_DIR="$1"
META_DIR="terraform/environments/homelab/$ENV_DIR/metadata"

if [[ ! -d "$META_DIR" ]]; then
  echo "❌ No metadata directory found at: $META_DIR"
  exit 1
fi

for FILE in "$META_DIR"/*.json; do
  [[ -e "$FILE" ]] || continue
  VM_NAME=$(basename "$FILE" .json)
  echo "🔍 Syncing $VM_NAME from $FILE"

  jq -r 'to_entries[] | "\(.key)=\(.value)"' "$FILE" | while IFS='=' read -r KEY VALUE; do
    echo "💾 $VM_NAME -> $KEY=$VALUE"
    curl -s --request PUT \
      --header "X-Consul-Token: $CONSUL_HTTP_TOKEN" \
      --data "$VALUE" \
      "$CONSUL_HTTP_ADDR/v1/kv/home-ops/vm/metadata/homelab/$VM_NAME/$KEY" > /dev/null
  done

done

echo "🚀 Metadata sync complete for environment: $ENV_DIR"
