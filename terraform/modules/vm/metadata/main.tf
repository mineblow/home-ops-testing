resource "local_file" "metadata" {
  for_each = proxmox_virtual_environment_vm.vm

  filename = "${path.root}/metadata/${each.key}.json"
  content = jsonencode({
    name       = each.key
    role       = each.value.role
    vmid       = each.value.vmid
    os_version = var.derived_os_version[each.key]
    notes      = var.notes[each.key]
    ip         = try(each.value.ipv4_addresses[1][0], null)
  })
}
