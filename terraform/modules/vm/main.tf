resource "tls_private_key" "vm" {
  for_each  = var.vm_config
  algorithm = "ED25519"
}

resource "vault_kv_secret_v2" "vm_ssh_key_private" {
  for_each = var.vm_config

  mount = "kv"
  name  = "home-ops/environment/homelab/${each.key}/secrets/vm_ssh_key_private"

  data_json = jsonencode({
    value = tls_private_key.vm[each.key].private_key_openssh
  })
}

resource "vault_kv_secret_v2" "vm_ssh_key_public" {
  for_each = var.vm_config

  mount = "kv"
  name  = "home-ops/environment/homelab/${each.key}/secrets/vm_ssh_key_public"

  data_json = jsonencode({
    value = tls_private_key.vm[each.key].public_key_openssh
  })
}

resource "proxmox_virtual_environment_vm" "vm" {
  for_each = var.vm_config

  name      = each.key
  vm_id     = each.value.vmid
  node_name = each.value.target_node

  description = lookup(local.role_descriptions, each.value.role, "Generic VM")

  clone {
    vm_id = each.value.template_vmid
    full  = true
  }

  cpu {
    cores   = each.value.cores
    sockets = each.value.sockets
    type    = "host"
  }

  memory {
    dedicated = each.value.memory
  }

  disk {
    interface    = "scsi0"
    size         = each.value.disk_size
    datastore_id = each.value.storage
    discard      = "on"
    iothread     = true
  }

  network_device {
    bridge = each.value.bridge
    model  = "virtio"
  }

  agent {
    enabled = true
  }

  operating_system {
    type = "other"
  }

  initialization {
    datastore_id      = "snippets-store"

    user_account {
      username = each.value.cloudinit_user
      password = each.value.cloudinit_password
      keys     = [tls_private_key.vm[each.key].public_key_openssh]
    }

    ip_config {
      ipv4 {
        address = "dhcp"
      }
    }

    user_data_file_id = "snippets/${local.derived_os_version[each.key]}.yaml"
  }

  tags = local.augmented_tags[each.key]
}

module "metadata" {
  source             = "./metadata"
  vm_config          = var.vm_config
  derived_os_version = local.derived_os_version
  notes              = { for name, cfg in var.vm_config : name => cfg.notes }
  vm_resources       = { for name, vm in proxmox_virtual_environment_vm.vm : name => {
    role            = var.vm_config[name].role
    vmid            = vm.vm_id
    ipv4_addresses  = vm.ipv4_addresses
  } }
}
