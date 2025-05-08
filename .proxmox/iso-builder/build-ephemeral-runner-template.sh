#!/bin/bash
set -euo pipefail

# ─── CONFIG ─────────────────────────────────────────────────────────────
VMID_START=9100
VMID_END=9110
TEMPLATE_PREFIX="ephemeral-runner-template"
ISO_URL="https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img"
ISO_NAME="ubuntu-22.04-ephemeral-cloudimg-amd64.img"
ISO_PATH="/var/lib/vz/template/iso/${ISO_NAME}"
STORAGE_POOL="local-zfs"
CI_DISK="scsi0"
CLOUDINIT_SNIPPET="/var/lib/vz/snippets/cloudinit-ephemeral.yaml"
META_OUT="/var/lib/vz/template/ephemeral-runner.meta.json"
VMNAME="${TEMPLATE_PREFIX}-$(date +%Y-%m-%d)"

# ─────────────────────────────────────────
# 🔒 PRECHECKS
# ─────────────────────────────────────────
command -v qm >/dev/null || { echo "❌ qm not found (Proxmox CLI required)"; exit 1; }
command -v curl >/dev/null || { echo "❌ curl not found"; exit 1; }

# ─────────────────────────────────────────
# 🔄 SYNC GITHUB RUNNER IMAGE SCRIPTS
# ─────────────────────────────────────────
if [[ -d "$RUNNER_IMAGE_SOURCE/.git" ]]; then
  echo "🔄 Pulling updates to actions/runner-images..."
  git -C "$RUNNER_IMAGE_SOURCE" pull --quiet
elif [[ -d "$RUNNER_IMAGE_SOURCE/images/linux/ubuntu2204" ]]; then
  echo "⚠️ Found runner scripts but not a git repo. Not updating."
else
  echo "📥 Cloning actions/runner-images for the first time..."
  git clone https://github.com/actions/runner-images.git "$RUNNER_IMAGE_SOURCE"
fi

# ─────────────────────────────────────────
# 📥 ISO DOWNLOAD
# ─────────────────────────────────────────
echo "📥 Downloading ISO..."
curl -fLo "$ISO_PATH" "$ISO_URL"

# ─────────────────────────────────────────
# 🔢 FIND OR RECLAIM VMID
# ─────────────────────────────────────────
echo "🎲 Finding available VMID..."
VMID=""
for ((i=VMID_START; i<=VMID_END; i++)); do
  if ! qm status "$i" &>/dev/null; then
    VMID="$i"
    break
  fi
done
if [[ -z "$VMID" ]]; then
  echo "♻️ No free VMID, reclaiming oldest..."
  OLDEST_VMID=$(qm list | awk '$2 ~ /^'"$TEMPLATE_PREFIX"'/ { print $1","$2 }' | sort -t, -k2 | head -n1 | cut -d, -f1)
  [[ -n "$OLDEST_VMID" ]] || { echo "❌ No free/reclaimable VMIDs"; exit 1; }
  echo "🔥 Destroying VMID $OLDEST_VMID"
  qm destroy "$OLDEST_VMID" --purge
  VMID="$OLDEST_VMID"
fi

# ─────────────────────────────────────────
# 🧱 CREATE VM + DISK
# ─────────────────────────────────────────
echo "🧱 Creating VM $VMID..."
qm create "$VMID" \
  --name "$VMNAME" \
  --memory 4096 \
  --cores 2 \
  --cpu cputype=kvm64 \
  --net0 virtio,bridge=vmbr0 \
  --scsihw virtio-scsi-single \
  --boot c \
  --bootdisk "$CI_DISK" \
  --ostype l26 \
  --agent enabled=1 \
  --serial0 socket \
  --vga serial0

echo "💽 Importing disk..."
qm importdisk "$VMID" "$ISO_PATH" "$STORAGE_POOL" --format raw
qm set "$VMID" \
  --$CI_DISK "$STORAGE_POOL:vm-${VMID}-disk-0,cache=writeback" \
  --ide2 "$STORAGE_POOL:cloudinit" \
  --ipconfig0 ip=dhcp \
  --ciuser ubuntu \
  --cipassword changeme

# ─── BOOT + INSTALL ─────────────────────────────────────────────────────
qm start "$VMID"
echo "⏳ Waiting for VM to boot (45s)..."
sleep 45

echo "⚙️ Installing deps + GitHub runner..."
qm guest exec "$VMID" -- bash -c "apt update && apt install -y qemu-guest-agent curl unzip git"
qm guest exec "$VMID" -- bash -c "
cd /opt && curl -LO https://github.com/actions/runner/releases/download/v2.316.0/actions-runner-linux-x64-2.316.0.tar.gz && \
mkdir -p actions-runner && tar -xf actions-runner-linux-x64-2.316.0.tar.gz -C actions-runner && rm actions-runner-linux-x64-2.316.0.tar.gz
"

qm guest exec "$VMID" -- bash -c "cloud-init clean"
qm shutdown "$VMID"
sleep 10

# ─── CLOUDINIT FOR REGISTRATION ─────────────────────────────────────────
echo "📄 Writing cloud-init firstboot..."
cat <<EOF > "$CLOUDINIT_SNIPPET"
#cloud-config
write_files:
  - path: /usr/local/bin/firstboot.sh
    permissions: '0755'
    content: |
      #!/bin/bash
      echo "[firstboot] Registering GitHub runner..."
      export VAULT_ADDR="http://vault.service.consul:8200"
      export VAULT_TOKEN=\$(cat /etc/vault.token)
      VAULT_PATH=\$(awk -F= '/^path=/{print \$2}' /etc/vault_path.cfg)
      RUNNER_TOKEN=\$(vault kv get -field=runner_token "\$VAULT_PATH")
      cd /opt/actions-runner
      ./config.sh --url https://github.com/YOUR_ORG --token \$RUNNER_TOKEN --name \$(hostname) --labels ephemeral --unattended
      ./svc.sh install
      ./svc.sh start
runcmd:
  - /usr/local/bin/firstboot.sh
EOF

qm set "$VMID" --cicustom "user=snippets/cloudinit-ephemeral.yaml"

# ─── FINALIZE TEMPLATE ──────────────────────────────────────────────────
echo "📦 Finalizing template..."
qm set "$VMID" --autostart off
qm template "$VMID"
qm set "$VMID" --tags "cloudinit,ephemeral,runner-template"

# ─── METADATA ───────────────────────────────────────────────────────────
echo "🧾 Writing metadata..."
ISO_HASH=$(sha256sum "$ISO_PATH" | awk '{print $1}')
SCRIPT_HASH=$(sha256sum "$0" | awk '{print $1}')
CENTRAL_TIMESTAMP=$(TZ="America/Chicago" date '+%Y-%m-%dT%H:%M:%S%z')
cat <<EOF > "$META_OUT"
{
  "iso_hash": "$ISO_HASH",
  "script_hash": "$SCRIPT_HASH",
  "template_id": "$VMID",
  "timestamp": "$CENTRAL_TIMESTAMP",
  "os_version": "ubuntu-22.04",
  "template_name": "$VMNAME"
}
EOF

echo "✅ Runner template built: $VMNAME (VMID $VMID)"
