output "selected_pod" {
  value = var.pod_id
}

output "pfsense_vms" {
  value = {
    for key, vm in proxmox_virtual_environment_vm.pfsense :
    key => {
      name          = vm.name
      vm_id         = vm.vm_id
      node_name     = vm.node_name
      firewall_key  = key
      template_key  = local.firewalls[key].template_key
      template_name = local.firewalls[key].template_name
      template_vmid = local.firewalls[key].template_vmid
      vmnets        = local.firewalls[key].vmnets
    }
  }
}
