locals {
  packer_config = jsondecode(file("${path.root}/packer_config.json"))

  template    = local.packer_config[var.template_key]
  target_node = local.template.target_nodes[var.node_key]
  adapters    = local.packer_config.adapter_settings

  proxmox_url      = local.packer_config.url
  proxmox_username = local.packer_config.user
  proxmox_node     = try(local.target_node.node, var.node_key)

  config_xml_path        = "${path.root}/files/${var.template_key}_config.xml"
  remote_config_tmp      = "/root/config.xml"
  create_api_user_path   = "${path.root}/files/create_apiuser.php"
  remote_create_api_user = "/root/create_apiuser.php"
}

local "proxmox_token_secret" {
  expression = vault(var.proxmox_secret_vault_path, var.proxmox_secret_vault_key)
  sensitive  = true
}

local "pfsense_api_password" {
  expression = vault(var.pfsense_api_password_vault_path, var.pfsense_api_password_vault_key)
  sensitive  = true
}
