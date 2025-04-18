module "bootstrap-runner" {
  source    = "../../../modules/vm"
  vm_config = var.vm_config

  providers = {
    proxmox = proxmox
    vault   = vault
    tls     = tls
  }
}

provider "vault" {
  token_no_default_policy = true
  skip_child_token        = true
  address                 = var.vault_address
  token                   = var.vault_token
}