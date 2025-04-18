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

provider "vault" {
  token_no_default_policy = true
  skip_child_token        = true
  address                 = var.vault_address
  token                   = var.vault_token
}
