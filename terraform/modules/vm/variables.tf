variable "vm_config" {
  type = map(object({
    template_vmid      = number
    role               = string
    vmid               = number
    cores              = number
    sockets            = number
    memory             = number
    disk_size          = number
    storage            = string
    target_node        = string
    bridge             = string
    cloudinit_user     = string
    cloudinit_password = string
    tags               = list(string)
    ha = object({
      enabled = string
      group   = string
      state   = string
    })
    notes = string
  }))
}


variable "username" {
  description = "Default user injected via cloud-init"
  type        = string
  default     = "ubuntu"
}

variable "ssh_key_path" {
  description = "Path to SSH public key used in cloud-init"
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}
