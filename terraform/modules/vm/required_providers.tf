terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = ">= 0.74.1"
    }
    vault = {
      source = "hashicorp/vault"
    }
    tls = {
      source = "hashicorp/tls"
    }
  }
}
