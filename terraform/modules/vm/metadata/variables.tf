variable "vm_config" {
  type = any
}

variable "derived_os_version" {
  type = map(string)
}

variable "notes" {
  type = map(string)
}

variable "vm_resources" {
  description = "Map of VM resources by name"
  type        = any
}
