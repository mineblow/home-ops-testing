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
  type = map(object({
    role           = string
    vmid           = number
    ipv4_addresses = list(list(string))
  }))
}
