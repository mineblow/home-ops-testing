locals {
  template_version_map = {
    "ubuntu-2204" = [9000, 9001, 9002, 9003, 9004, 9005]
    "ubuntu-2404" = [9010, 9011, 9012, 9013, 9014, 9015]
  }

  derived_os_version = {
    for name, config in var.vm_config :
    name => try(
      [for os, ids in local.template_version_map : os if contains(ids, config.template_vmid)][0],
      "unknown"
    )
  }

  base_cloudinit = {
    for name, key in tls_private_key.vm :
    name => templatefile("${path.module}/cloudinit/${local.derived_os_version[name]}.yaml", {
      username = var.vm_config[name].cloudinit_user
      ssh_key  = trimspace(key.public_key_openssh)
    })
  }

  augmented_tags = {
    for name, cfg in var.vm_config :
    name => distinct([
      for tag in concat(
        ["cicd", "os-${local.derived_os_version[name]}", "role-${cfg.role}"],
        cfg.tags
      ) : replace(lower(tag), "[^a-z0-9_-]", "-")
    ])
  }

  role_descriptions = {
    "k3s-master"       = "K3s master node"
    "k3s-worker"       = "K3s worker node"
    "github-bootstrap" = "Bootstrap GitHub Actions runner"
    "github-runner"    = "Ephemeral GitHub Actions runner"
  }
}
