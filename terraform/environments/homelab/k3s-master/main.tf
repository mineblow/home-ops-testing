module "k3s-master" {
  source    = "../../../modules/vm"
  vm_config = var.vm_config

  providers = {
    proxmox = proxmox
    vault   = vault
    tls     = tls
  }
}

module "metadata" {
  source      = "../../../modules/vm/metadata"
  vm_config   = var.vm_config
  environment = "bootstrap-runner"
}
