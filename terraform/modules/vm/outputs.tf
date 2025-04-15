output "vm_names" {
  value = {
    for name, vm in proxmox_virtual_environment_vm.vm :
    name => vm.name
  }
}
