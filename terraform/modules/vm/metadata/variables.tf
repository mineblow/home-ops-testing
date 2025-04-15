variable "vm_config" {
  type = any
}

variable "derived_os_version" {
  type = map(string)
}

variable "notes" {
  type = map(string)
}
