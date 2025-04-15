resource "local_file" "metadata" {
  for_each = var.vm_config

  filename = "${path.root}/metadata/${each.key}.json"
  content = jsonencode({
    name       = each.key
    role       = each.value.role
    vmid       = each.value.vmid
    os_version = var.derived_os_version[each.key]
    notes      = var.notes[each.key]
  })
}
