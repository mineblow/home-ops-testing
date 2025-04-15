variable "vm_config" {
  type = map(object({
    role               = string
    vmid               = number
    template_vmid      = number
    cores              = number
    sockets            = number
    memory             = number
    disk_size          = number
    storage            = string
    snippet_storage    = string
    target_node        = string
    bridge             = string
    cloudinit_user     = string
    cloudinit_password = string
    tags               = list(string)

    ha = object({
      enabled = bool
      group   = string
      state   = string
    })
    notes = string
  }))
}


variable "gcp_project" {
  description = "GCP project ID (only needed if GCP is used)"
  type        = string
  default     = "" # or remove if unused
}

variable "proxmox_api_url" {
  description = "Proxmox API URL"
  type        = string
}

variable "proxmox_api_token" {
  description = "Proxmox API token"
  type        = string
  sensitive   = true
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

variable "proxmox_ssh_user" {
  description = "Username for SSH access to Proxmox nodes"
  type        = string
}

variable "proxmox_ssh_private_key" {
  description = "Path to private SSH key for Proxmox access"
  type        = string
}
