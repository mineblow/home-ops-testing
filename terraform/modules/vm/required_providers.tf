terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = ">= 0.74.1"
    }
    vault = {
      source = "hashicorp/vault"
      version = ">= 3.20.0"
    }
    tls = {
      source = "hashicorp/tls"
    }
  }
}

provider "vault" {
  alias                  = "nochild"
  address                = var.vault_address
  token                  = var.vault_token
  skip_child_token       = true
  token_no_default_policy = true
}