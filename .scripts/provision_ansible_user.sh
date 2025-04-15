#!/bin/bash

HOSTS=(192.168.1.51 192.168.1.52 192.168.1.53 192.168.1.54 192.168.1.55 192.168.1.56)
PUBKEY=$(cat ~/.ssh/ansible_id_rsa.pub)

read -s -p "Enter sudo password for user 'mineblow': " SUDO_PASS
echo ""

for host in "${HOSTS[@]}"; do
  echo "🔧 Provisioning $host ..."

  # Clean known_hosts entry if needed
  ssh-keygen -f ~/.ssh/known_hosts -R "$host" 2>/dev/null

  # Check SSH first
  sshpass -p "$SUDO_PASS" ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no mineblow@$host 'exit' 2>/dev/null
  if [ $? -ne 0 ]; then
    echo "❌ SSH failed for $host — skipping"
    continue
  fi

  # Execute everything in one inline block, no hang
  sshpass -p "$SUDO_PASS" ssh -tt -o StrictHostKeyChecking=no mineblow@$host "
    echo '$SUDO_PASS' | sudo -S useradd -m -s /bin/bash -G sudo ansible 2>/dev/null || true &&
    echo '$SUDO_PASS' | sudo -S mkdir -p /home/ansible/.ssh &&
    echo '$PUBKEY' | sudo tee /home/ansible/.ssh/authorized_keys >/dev/null &&
    sudo chown -R ansible:ansible /home/ansible/.ssh &&
    sudo chmod 700 /home/ansible/.ssh &&
    sudo chmod 600 /home/ansible/.ssh/authorized_keys &&
    echo 'ansible ALL=(ALL) NOPASSWD:ALL' | sudo tee /etc/sudoers.d/ansible >/dev/null &&
    sudo chmod 0440 /etc/sudoers.d/ansible
  "

  echo "✅ Done: $host"
done

echo "🎉 All hosts provisioned. Try: ssh -i ~/.ssh/ansible_id_rsa ansible@192.168.1.51"
