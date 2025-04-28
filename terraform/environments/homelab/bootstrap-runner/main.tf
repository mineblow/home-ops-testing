module "bootstrap-runner" {
  source    = "../../../modules/vm"
  vm_config = var.vm_config

  providers = {
    proxmox = proxmox
    vault   = vault
    tls     = tls
  }
}
