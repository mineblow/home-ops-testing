#!/usr/bin/env bash
set -euo pipefail

VAULT_VERSION="1.15.5"

echo "📦 Installing Vault CLI v$VAULT_VERSION..."

# Download and extract
curl -fsSL "https://releases.hashicorp.com/vault/${VAULT_VERSION}/vault_${VAULT_VERSION}_linux_amd64.zip" -o vault.zip
unzip -q vault.zip

# Install
sudo install vault /usr/local/bin/vault
vault --version

# Cleanup
rm -f vault vault.zip
