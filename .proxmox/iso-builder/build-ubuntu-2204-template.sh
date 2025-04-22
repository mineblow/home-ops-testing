#!/bin/bash
set -euo pipefail

# ─────────────────────────────────────────
# ⚙️ CONFIGURATION
# ─────────────────────────────────────────
VMID_START=9000
VMID_END=9005
MAX_TEMPLATES=5
TEMPLATE_PREFIX="ubuntu-22.04-cloudinit"
ISO_URL="https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img"
ISO_NAME="ubuntu-22.04-cloudimg-amd64.img"
ISO_PATH="/var/lib/vz/template/iso/${ISO_NAME}"
STORAGE_POOL="local-zfs"
CI_DISK="scsi0"
NODE="proxmox"
TODAY=$(date +%Y-%m-%d)
VMNAME="${TEMPLATE_PREFIX}-${TODAY}"

# ─────────────────────────────────────────
# 🔒 PRECHECKS
# ─────────────────────────────────────────
command -v qm >/dev/null || { echo "❌ qm not found (Proxmox CLI required)"; exit 1; }
command -v curl >/dev/null || { echo "❌ curl not found"; exit 1; }

# ─────────────────────────────────────────
# 📥 ISO DOWNLOAD
# ─────────────────────────────────────────
echo "📥 Downloading latest ISO..."
curl -fLo "$ISO_PATH" "$ISO_URL"

# ─────────────────────────────────────────
# 🔢 DYNAMIC VMID ALLOCATION
# ─────────────────────────────────────────
echo "🎲 Finding available VMID..."
for ((i=VMID_START; i<=VMID_END; i++)); do
  if ! qm status "$i" &>/dev/null; then
    VMID="$i"
    break
  fi
done

if [[ -z "${VMID:-}" ]]; then
  echo "❌ No free VMID between $VMID_START and $VMID_END."
  exit 1
fi

# ─────────────────────────────────────────
# 🧱 CREATE BASE VM
# ─────────────────────────────────────────
echo "🧱 Creating VM $VMID..."
qm create "$VMID" \
  --name "$VMNAME" \
  --memory 2048 \
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
# 📄 SKIP INLINE CLOUD-INIT
# ─────────────────────────────────────────
echo "🧼 Skipping inline cloud-init. Terraform will inject YAML snippets later."

# ─────────────────────────────────────────
# 🪄 FINALIZE TEMPLATE
# ─────────────────────────────────────────
qm set "$VMID" --autostart off
qm template "$VMID"
qm set "$VMID" --tags "cloudinit,ubuntu,auto-built"

# ─────────────────────────────────────────
# 🧹 DELETE OLD TEMPLATES
# ─────────────────────────────────────────
echo "🧹 Deleting old templates..."
TEMPLATES=$(qm list | grep "$TEMPLATE_PREFIX" | awk '{print $1,$2,$3}' | sort -k3 -r)
TEMPLATE_IDS=($(echo "$TEMPLATES" | awk '{print $1}'))

for ((i=MAX_TEMPLATES; i<${#TEMPLATE_IDS[@]}; i++)); do
  OLD_VMID="${TEMPLATE_IDS[$i]}"
  echo "🔥 Destroying VMID $OLD_VMID"
  qm destroy "$OLD_VMID" --purge
done

# ─────────────────────────────────────────
# 🏷️ RETAG TEMPLATES
# ─────────────────────────────────────────
echo "🏷️ Retagging templates..."
ALL_VMS=($(qm list | grep "$TEMPLATE_PREFIX" | sort -k3 -r | awk '{print $1}'))
for i in "${!ALL_VMS[@]}"; do
  tag="retired"
  [[ $i -eq 0 ]] && tag="active"
  qm set "${ALL_VMS[$i]}" --tags "cloudinit,ubuntu,auto-built,$tag"
done

# ─────────────────────────────────────────
# 🧾 BUILD METADATA
# ─────────────────────────────────────────
echo "🧾 Building metadata..."
ISO_HASH=$(sha256sum "$ISO_PATH" | awk '{print $1}')
SCRIPT_PATH="$(realpath "${BASH_SOURCE[0]}")"
SCRIPT_HASH=$(sha256sum "$SCRIPT_PATH" | awk '{print $1}')
CENTRAL_TIMESTAMP=$(TZ="America/Chicago" date '+%Y-%m-%dT%H:%M:%S%z')
META_OUT="/var/lib/vz/template/${TEMPLATE_PREFIX}-${TODAY}.meta.json"

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


# ─────────────────────────────────────────
# 📝 Logging (optional)
# ─────────────────────────────────────────
# echo "$(date -u) - Built $VMNAME (VMID $VMID)" >> /var/log/template-builder.log
