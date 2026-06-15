variable "template_key" {
  type        = string
  description = "Key from packer_config.json, for example pfsense_template_01."
}

variable "node_key" {
  type        = string
  description = "Target node key from packer_config.json target_nodes."
}

variable "template_description" {
  type        = string
  description = "Description shown in the Proxmox template notes."
  default     = "pfSense CE 2.8.1 template"
}

variable "pfsense_img_path" {
  type        = string
  description = "Proxmox datastore path to the pfSense ISO."
  default     = "local:iso/netgate-installer-amd64.iso"
}

variable "pfsense_img_checksum" {
  type        = string
  description = "pfSense ISO SHA256 checksum."
  default     = "sha256:f6520bb14a5e690c6533e4e8fbf4a48d2967f3bc35a713e716b9c64317a13f23"
}

variable "pfsense_build_user" {
  type        = string
  description = "SSH user used by Packer during provisioning."
  default     = "root"
}

variable "pfsense_build_pass" {
  type        = string
  description = "SSH password used by Packer during provisioning."
  default     = "pfsense"
  sensitive   = true
}

variable "pfsense_api_user" {
  type        = string
  description = "Local pfSense user created for REST API automation."
  default     = "apiuser"
}

variable "proxmox_secret_vault_path" {
  type        = string
  description = "Vault KV v2 path that contains the Proxmox API token secret."
  default     = "NetOps/data/infra-nonprod"
}

variable "proxmox_secret_vault_key" {
  type        = string
  description = "Vault key that contains the Proxmox API token secret."
  default     = "proxmox_token_secret"
}

variable "pfsense_api_password_vault_path" {
  type        = string
  description = "Vault KV v2 path that contains the pfSense API user password."
  default     = "NetOps/data/infra-nonprod"
}

variable "pfsense_api_password_vault_key" {
  type        = string
  description = "Vault key that contains the pfSense API user password."
  default     = "pfsense_api_password"
}

variable "pfsense_vm_ram" {
  type        = number
  description = "RAM in MB."
  default     = 8192
}

variable "pfsense_vm_cores" {
  type        = number
  description = "CPU cores; also used for virtio multiqueue packet_queues."
  default     = 4
}

variable "disk_size" {
  type        = string
  description = "Template disk size."
  default     = "10G"
}

variable "disk_storage_pool" {
  type        = string
  description = "Proxmox storage pool for the VM disk."
  default     = "local-lvm"
}
