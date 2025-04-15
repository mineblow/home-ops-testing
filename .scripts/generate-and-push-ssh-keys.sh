#!/usr/bin/env bash
set -euo pipefail

# CONFIG: List all your VM names here
VM_LIST=("k3s-master-0" "k3s-master-1" "k3s-master-2")

# Output dir for generated keys
KEY_DIR="ssh_keys"
mkdir -p "$KEY_DIR"

echo "🔐 Generating SSH keys for: ${VM_LIST[*]}"
for vm in "${VM_LIST[@]}"; do
  ssh-keygen -t rsa -b 4096 -N "" -f "${KEY_DIR}/${vm}" <<< y >/dev/null
done

echo "📦 Building JSON secret payload"
SECRET_JSON="ssh_keys.json"
echo "{" > "$SECRET_JSON"
for vm in "${VM_LIST[@]}"; do
  pub_key=$(<"${KEY_DIR}/${vm}.pub")
  priv_key=$(<"${KEY_DIR}/${vm}")

  # Escape newlines for JSON string (safe for GCP)
  escaped_priv_key=$(printf %q "$priv_key" | sed 's/\\n/\\\\n/g')

  echo "  \"$vm\": {" >> "$SECRET_JSON"
  echo "    \"public_key\": \"${pub_key}\"," >> "$SECRET_JSON"
  echo "    \"private_key\": \"${escaped_priv_key}\"" >> "$SECRET_JSON"
  echo "  }," >> "$SECRET_JSON"
done
# Remove trailing comma from last entry
sed -i '$ s/},/}/' "$SECRET_JSON"
echo "}" >> "$SECRET_JSON"

echo "☁️ Uploading to GCP Secret Manager..."

# Check if the secret exists
if gcloud secrets describe ssh_keys >/dev/null 2>&1; then
  echo "✅ Found existing 'ssh_keys' secret, adding new version..."
else
  echo "🚀 Creating 'ssh_keys' secret..."
  gcloud secrets create ssh_keys --replication-policy="automatic"
fi

# Upload the new version
gcloud secrets versions add ssh_keys --data-file="$SECRET_JSON"

echo "🎉 All done! SSH keys injected. Ready to Terraform."
