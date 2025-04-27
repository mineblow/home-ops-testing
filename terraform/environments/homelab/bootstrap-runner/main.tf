module "bootstrap-runner" {
  source    = "../../../modules/vm"
  vm_config = var.vm_config
  derived_os_version = local.derived_os_version
  
  providers = {
    proxmox = proxmox
    vault   = vault
    tls     = tls
  }
}
