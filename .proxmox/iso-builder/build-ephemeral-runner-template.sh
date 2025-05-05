#!/bin/bash
set -euo pipefail

# ─────────────────────────────────────────
# ⚙️ CONFIGURATION
# ─────────────────────────────────────────
VMID_START=9100
VMID_END=9110
TEMPLATE_PREFIX="ephemeral-runner-template"
ISO_URL="https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img"
ISO_NAME="ubuntu-22.04-ephemeral-cloudimg-amd64.img"
ISO_PATH="/var/lib/vz/template/iso/${ISO_NAME}"
STORAGE_POOL="local-zfs"
CI_DISK="scsi0"
TODAY=$(date +%Y-%m-%d)
VMNAME="${TEMPLATE_PREFIX}-${TODAY}"
META_OUT="/var/lib/vz/template/ephemeral-runner.meta.json"
RUNNER_IMAGE_SOURCE="/opt/github-runner-image"

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
echo "📥 Downloading latest ISO..."
curl -fLo "$ISO_PATH" "$ISO_URL"

# ─────────────────────────────────────────
# 🔢 DYNAMIC VMID ALLOCATION + OLDEST RECLAIM
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
  if [[ -n "$OLDEST_VMID" ]]; then
    echo "🔥 Reclaiming VMID $OLDEST_VMID"
    qm destroy "$OLDEST_VMID" --purge
    VMID="$OLDEST_VMID"
  else
    echo "❌ No reclaimable template found."
    exit 1
  fi
fi

# ─────────────────────────────────────────
# 🧱 CREATE BASE VM
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

# ─────────────────────────────────────────
# 💽 IMPORT DISK
# ─────────────────────────────────────────
echo "💽 Importing disk..."
qm importdisk "$VMID" "$ISO_PATH" "$STORAGE_POOL" --format raw
qm set "$VMID" \
  --$CI_DISK "$STORAGE_POOL:vm-${VMID}-disk-0,cache=writeback" \
  --ide2 "$STORAGE_POOL:cloudinit" \
  --ciuser ubuntu \
  --cipassword changeme \
  --ipconfig0 ip=dhcp

# ─────────────────────────────────────────
# 🔧 INSTALL GITHUB TOOLCHAIN IN ROOTFS
# ─────────────────────────────────────────
echo "🔧 Injecting GitHub runner toolchain..."

DISK_PATH="/dev/zvol/${STORAGE_POOL}/vm-${VMID}-disk-0"
MOUNT_DIR="/mnt/vm-${VMID}"
mkdir -p "$MOUNT_DIR"

zfs set mountpoint="$MOUNT_DIR" "${STORAGE_POOL}/vm-${VMID}-disk-0"
mount "$DISK_PATH" "$MOUNT_DIR"

mount --bind /dev "$MOUNT_DIR/dev"
mount --bind /proc "$MOUNT_DIR/proc"
mount --bind /sys "$MOUNT_DIR/sys"

cp -r "$RUNNER_IMAGE_SOURCE" "$MOUNT_DIR/opt/github-runner-image"

chroot "$MOUNT_DIR" bash -c "
  cd /opt/github-runner-image/images/linux/ubuntu2204
  chmod +x ./main.sh
  ./main.sh
"

rm -rf "$MOUNT_DIR/opt/github-runner-image"
umount -lf "$MOUNT_DIR/dev"
umount -lf "$MOUNT_DIR/proc"
umount -lf "$MOUNT_DIR/sys"
umount -lf "$MOUNT_DIR"
rmdir "$MOUNT_DIR"

echo "✅ GitHub runner image baked into rootfs"

# ─────────────────────────────────────────
# 📁 INJECT CLOUD-INIT FIRSTBOOT + CONFIG
# ─────────────────────────────────────────
CLOUDINIT_SNIPPET="/var/lib/vz/snippets/cloudinit-ephemeral.yaml"
mkdir -p "$(dirname "$CLOUDINIT_SNIPPET")"
cat <<EOF > "$CLOUDINIT_SNIPPET"
#cloud-config
write_files:
  - path: /usr/local/bin/firstboot.sh
    permissions: '0755'
    content: |
      #!/bin/bash
      echo "[firstboot] Starting GitHub runner registration..."

      export VAULT_ADDR="http://vault.service.consul:8200"
      export VAULT_TOKEN=\$(cat /etc/vault.token)
      VAULT_PATH=\$(awk -F= '/^path=/{print \$2}' /etc/vault_path.cfg)
      RUNNER_TOKEN=\$(vault kv get -field=runner_token "\$VAULT_PATH")

      cd /opt/actions-runner
      ./config.sh --url https://github.com/YOUR_ORG \
                  --token "\$RUNNER_TOKEN" \
                  --name "\$(hostname)" \
                  --labels ephemeral \
                  --unattended
      ./svc.sh install
      ./svc.sh start
runcmd:
  - /usr/local/bin/firstboot.sh
EOF

qm set "$VMID" --cicustom "user=snippets/cloudinit-ephemeral.yaml"

# ─────────────────────────────────────────
# 🪄 FINALIZE TEMPLATE
# ─────────────────────────────────────────
qm set "$VMID" --autostart off
qm template "$VMID"
qm set "$VMID" --tags "cloudinit,ephemeral,runner-template"

# ─────────────────────────────────────────
# 🧾 BUILD METADATA
# ─────────────────────────────────────────
echo "🧾 Building metadata..."
ISO_HASH=$(sha256sum "$ISO_PATH" | awk '{print $1}')
SCRIPT_PATH="$(realpath "${BASH_SOURCE[0]}")"
SCRIPT_HASH=$(sha256sum "$SCRIPT_PATH" | awk '{print $1}')
CENTRAL_TIMESTAMP=$(TZ="America/Chicago" date '+%Y-%m-%dT%H:%M:%S%z')

cat <<EOF > "$META_OUT"
{
  "iso_hash": "${ISO_HASH}",
  "script_hash": "${SCRIPT_HASH}",
  "template_id": "${VMID}",
  "timestamp": "${CENTRAL_TIMESTAMP}",
  "os_version": "ubuntu-22.04",
  "template_name": "${VMNAME}"
}
EOF

echo "📦 Metadata saved to: $META_OUT"
