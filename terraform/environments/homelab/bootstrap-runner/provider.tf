terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "= 0.76.0"
    }
    vault = {
      source = "hashicorp/vault"
      version = "= 4.7.0"
    }
    tls = {
      source = "hashicorp/tls"
      version = "= 4.0.6"
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

provider "vault" {}
provider "tls" {}
