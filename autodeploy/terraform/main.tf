resource "proxmox_virtual_environment_vm" "pfsense" {
  for_each = local.firewalls

  name        = each.value.hostname
  description = "${var.description}: ${var.pod_id}/${each.key}, clone from ${each.value.template_name}"
  tags        = distinct(concat(var.tags, [var.location, var.pod_id, each.key]))
  pool_id     = var.pool_id

  node_name = each.value.pm_node
  vm_id     = each.value.vm_id

  started         = var.started
  on_boot         = var.on_boot
  protection      = var.protection
  stop_on_destroy = var.stop_on_destroy
  reboot          = var.reboot

  acpi          = var.acpi
  bios          = var.bios
  machine       = var.machine
  tablet_device = var.tablet_device
  boot_order    = var.boot_order

  timeout_clone       = var.timeout_clone
  timeout_start_vm    = var.timeout_start_vm
  timeout_stop_vm     = var.timeout_stop_vm
  timeout_shutdown_vm = var.timeout_shutdown_vm
  timeout_reboot      = var.timeout_reboot

  clone {
    vm_id        = each.value.template_vmid
    node_name    = each.value.pm_node
    full         = var.clone_full
    datastore_id = var.clone_datastore_id
    retries      = var.clone_retries
  }

  operating_system {
    type = var.operating_system_type
  }

  agent {
    enabled = var.agent_enabled
    type    = var.agent_type
    trim    = var.agent_trim
    timeout = var.agent_timeout
  }

  cpu {
    # architecture = var.cpu_architecture
    cores        = var.cpu_cores
    sockets      = var.cpu_sockets
    type         = var.cpu_type
    flags        = var.cpu_flags
    numa         = var.cpu_numa
  }

  memory {
    dedicated      = var.memory_dedicated
    floating       = var.memory_floating
    shared         = var.memory_shared
    hugepages      = var.memory_hugepages
    keep_hugepages = var.memory_keep_hugepages
  }

  dynamic "startup" {
    for_each = var.startup_order == null ? [] : [1]

    content {
      order      = var.startup_order
      up_delay   = var.startup_up_delay
      down_delay = var.startup_down_delay
    }
  }

  dynamic "network_device" {
    for_each = each.value.vmnets

    content {
      bridge       = try(network_device.value.bridge, var.network_bridge)
      model        = try(network_device.value.model, var.network_model)
      vlan_id      = try(tonumber(network_device.value.vlan), null)
      firewall     = try(network_device.value.firewall, var.network_firewall)
      queues       = try(network_device.value.queues, var.network_queues)
      mtu          = try(network_device.value.mtu, var.network_mtu)
      rate_limit   = try(network_device.value.rate_limit, var.network_rate_limit)
      disconnected = try(network_device.value.disconnected, var.network_disconnected)
    }
  }

  lifecycle {
    precondition {
      condition     = each.value.template_vmid != null
      error_message = "Missing ${each.value.template_key}.target_nodes.${each.value.pm_node}.vmid in packer_config.yaml for ${var.pod_id}/${each.key}."
    }

    precondition {
      condition     = length(each.value.vmnets) > 0
      error_message = "Missing vmnets list in firewall_config.yaml for POD ${var.pod_id}."
    }

    ignore_changes = [
      # Proxmox sorts tags and templates can have inherited settings.
      tags,
    ]
  }
}
