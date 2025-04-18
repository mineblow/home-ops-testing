terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "= 0.74.1"
    }
    vault = {
      source = "hashicorp/vault"
      version = "= 3.20.0"
    }
    tls = {
      source = "hashicorp/tls"
    }
  }
}
