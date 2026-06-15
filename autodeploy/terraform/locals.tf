locals {
  firewall_config = yamldecode(file(var.firewall_config_path))
  packer_config   = yamldecode(file(var.packer_config_path))

  location_config = local.packer_config.packer[var.location]
  pod_config      = local.firewall_config[var.pod_id]

  # bpg/proxmox provider endpoint must not include /api2/json.
  proxmox_endpoint = trimsuffix(local.location_config.url, "/api2/json")
  proxmox_api_user = local.location_config.user

  template_key_by_firewall = {
    firewall_01 = "pfsense_template_01"
    firewall_02 = "pfsense_template_02"
  }

  selected_firewalls = {
    for firewall_key, firewall in local.pod_config :
    firewall_key => firewall
    if contains(keys(local.template_key_by_firewall), firewall_key)
  }

  vmnets = try(local.pod_config.vmnets, [])

  firewalls = {
    for firewall_key, firewall in local.selected_firewalls :
    firewall_key => {
      firewall_key  = firewall_key
      hostname      = firewall.hostname
      pm_node       = firewall.pm_node
      wan_ip        = try(firewall.wan_ip, null)
      lan_ip        = try(firewall.lan_ip, null)

      template_key  = local.template_key_by_firewall[firewall_key]
      template_name = local.location_config[local.template_key_by_firewall[firewall_key]].name
      template_vmid = try(local.location_config[local.template_key_by_firewall[firewall_key]].target_nodes[firewall.pm_node].vmid, null)

      vm_id         = try(var.vm_ids[firewall_key], null)

      # Keep order from firewall_config.yaml:
      # vtnet0 -> net0, vtnet1 -> net1, vtnet2 -> net2, etc.
      vmnets        = local.vmnets
    }
  }
}
