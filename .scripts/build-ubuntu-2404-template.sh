#!/bin/bash
set -euo pipefail

# ─────────────────────────────────────────
# ⚙️ CONFIGURATION
# ─────────────────────────────────────────
VMID_START=9000
VMID_END=9005
MAX_TEMPLATES=5
TEMPLATE_PREFIX="ubuntu-24.04-cloudinit"
ISO_URL="https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
ISO_NAME="ubuntu-24.04-cloudimg-amd64.img"
ISO_PATH="/var/lib/vz/template/iso/${ISO_NAME}"
ISO_META_PATH="${ISO_PATH}.meta"
STORAGE_POOL="local-zfs"
CI_DISK="scsi0"
NODE="proxmox"
TODAY=$(date +%Y-%m-%d)
VMNAME="${TEMPLATE_PREFIX}-${TODAY}"
GIT_COMMIT_HASH=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")

# ─────────────────────────────────────────
# 🔒 PRECHECKS
# ─────────────────────────────────────────
command -v qm >/dev/null || { echo "❌ qm not found (Proxmox CLI required)"; exit 1; }
command -v curl >/dev/null || { echo "❌ curl not found"; exit 1; }

# ─────────────────────────────────────────
# 📦 ISO MANAGEMENT
# ─────────────────────────────────────────
echo "📦 Checking ISO version..."
LATEST_SHA256=$(curl -sI "${ISO_URL}" | grep -i 'etag:' | cut -d '"' -f2 || true)

if [[ -f "$ISO_META_PATH" && -n "$LATEST_SHA256" ]] && grep -q "$LATEST_SHA256" "$ISO_META_PATH"; then
  echo "✅ ISO is up to date."
else
  echo "📥 Downloading latest ISO..."
  curl -fLo "$ISO_PATH" "$ISO_URL"
  echo "$LATEST_SHA256" > "$ISO_META_PATH"

  echo "🧹 Cleaning up old ISO files..."
  find /var/lib/vz/template/iso/ -type f -name "${TEMPLATE_PREFIX}*.img" ! -newer "$ISO_META_PATH" -delete
  find /var/lib/vz/template/iso/ -type f -name "${TEMPLATE_PREFIX}*.meta" ! -newer "$ISO_META_PATH" -delete
fi

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
# 📋 SUMMARY
# ─────────────────────────────────────────
echo "✅ Template Created:"
echo "   🆔 VMID: $VMID"
echo "   🏷️ Name: $VMNAME"
echo "   💾 Pool: $STORAGE_POOL"
echo "   📅 Built: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo "   🧬 Version: ubuntu-24.04"
echo "   🔖 Commit: $GIT_COMMIT_HASH"

# ─────────────────────────────────────────
# 📝 LOGGING (optional)
# ─────────────────────────────────────────
# LOGFILE="/var/log/template-builder.log"
# exec > >(tee -a "$LOGFILE") 2>&1
