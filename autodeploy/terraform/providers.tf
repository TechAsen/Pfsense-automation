provider "proxmox" {
  endpoint      = local.proxmox_endpoint
  api_token     = "${local.proxmox_api_user}=${var.proxmox_token_secret}"
  insecure      = var.proxmox_insecure
  random_vm_ids = var.random_vm_ids
}
