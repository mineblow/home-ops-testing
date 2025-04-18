terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = ">= 0.74.1"
    }
    vault = {
      source = "hashicorp/vault"
      token_no_default_policy = true
      skip_child_token        = true
    }
    tls = {
      source = "hashicorp/tls"
    }
  }
}
