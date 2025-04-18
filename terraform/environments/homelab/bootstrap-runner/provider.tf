terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = ">= 0.74.1"
    }
    tls = {
      source = "hashicorp/tls"
    }
    vault = {
      source = "hashicorp/vault"
    }
  }
}

provider "proxmox" {
  endpoint  = var.proxmox_api_url
  api_token = var.proxmox_api_token
  insecure  = true

  ssh {
    username    = var.proxmox_ssh_user
    private_key = file(var.proxmox_ssh_private_key)
  }
}

provider "vault" {
  token_no_default_policy = true
  skip_child_token        = true
  address                 = var.vault_address
  token                   = var.vault_token
}
provider "tls" {}
