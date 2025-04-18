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
