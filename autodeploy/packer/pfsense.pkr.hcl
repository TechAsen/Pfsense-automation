source "proxmox-iso" "pfsense" {
  template_name        = local.template.name
  template_description = var.template_description

  proxmox_url              = local.proxmox_url
  username                 = local.proxmox_username
  token                    = local.proxmox_token_secret
  insecure_skip_tls_verify = true

  node  = local.proxmox_node
  vm_id = local.target_node.vmid

  machine         = "q35"
  os              = "l26"
  scsi_controller = "virtio-scsi-single"
  qemu_agent      = true
  cpu_type        = "host"
  sockets         = 1
  cores           = var.pfsense_vm_cores
  memory          = var.pfsense_vm_ram

  # 0 disables ballooning. Keep it disabled for deterministic firewall/router performance.
  ballooning_minimum = 0


  # After install/reboot, boot from the installed disk first, then ISO, then network.
  boot = "order=scsi0;scsi1;net0"

  boot_iso {
    type         = "scsi"
    iso_file     = var.pfsense_img_path
    iso_checksum = var.pfsense_img_checksum
    unmount      = true
  }

  disks {
    type         = "scsi"
    format       = "raw"
    io_thread    = true
    disk_size    = var.disk_size
    storage_pool = var.disk_storage_pool
  }

  # WAN = vtnet0. This must exist because the config.xml uses vtnet0 for WAN.
  network_adapters {
    model         = "virtio"
    bridge        = try(local.adapters.bridge, "vmbr0")
    vlan_tag      = "${try(local.adapters.wan_vlan, local.template.wan_vlan)}"
    packet_queues = var.pfsense_vm_cores
  }

  # LAN = vtnet1. This must exist because SSH provisioning uses local.template.lan_ipv4.
  network_adapters {
    model         = "virtio"
    bridge        = try(local.adapters.bridge, "vmbr0")
    vlan_tag      = "${try(local.adapters.lan_vlan, local.template.lan_vlan)}"
    packet_queues = var.pfsense_vm_cores
  }

  onboot    = true
  boot_wait = "40s"

  boot_command = [
    # Accept copyright
    "<enter><wait2s>",
    # Advanced Options
    "<right><enter><wait2s>",
    # Enable CE repository option, then save options
    "<down><enter><wait2s>",
    "<enter><wait2s>",
    # Welcome / Install
    "<enter><wait2s>",
    "<enter><wait2s>",

    # WAN Interface Assignment and Configuration
    "<enter><wait2s>",
    "<down><enter><wait2s>",
    "<down><down><down><enter><wait2s>",
    "${local.template.wan_ipv4}<enter><wait2s>",
    "<down><down><down><down><enter><wait2s>",
    "${local.adapters.gateway}<enter><wait2s>",
    "<down><down><down><down><down><enter><wait2s>",
    "${local.adapters.dns_server}<enter><wait2s>",
    "<enter><wait5s>",

    # LAN Interface Assignment and Configuration
    "<down><enter><wait5s>",
    "<down><down><down><enter><wait2s>",
    "<bs><bs><bs><bs><bs><bs><bs><bs><bs><bs><bs><bs><bs><bs><wait2s>",
    "${local.template.lan_ipv4}<enter><wait2s>",
    "<down><down><down><down><enter><wait2s>",
    "<enter><wait5s>",
    "<enter><wait70s>",
    "<enter>",

    # Installation Options / ZFS stripe / disk / confirmation / install
    "<enter><wait2s>",
    "<enter><wait2s>",
    "<enter><wait2s>",
    "<enter><wait5s>",
    "<enter><wait1320s>",
    "<enter><wait2s>",

    # Complete / Reboot. Give pfSense enough time to boot from the installed disk.
    "<enter><wait150s>",

    # Enable SSH and temporarily disable pf firewall for provisioning.
    # After option 14, enter shell and force-start sshd as a fallback.
    "14<enter><wait5s>",
    "y<enter><wait5s>",
    "8<enter><wait5s>",
    "pfctl -d<enter><wait2s>",
    # "/etc/rc.d/sshd onestart<enter><wait5s>",
    # "sockstat -4 -l | grep ':22'<enter><wait20s>"
  ]

  communicator = "ssh"
  ssh_username = var.pfsense_build_user
  ssh_password = var.pfsense_build_pass
  ssh_host     = local.template.lan_ipv4

  # Wait a little after boot_command before Packer starts SSH attempts.
  pause_before_connecting = "30s"
  ssh_timeout             = "90m"
  ssh_handshake_attempts  = 300
  ssh_pty                 = true
}

build {
  sources = ["source.proxmox-iso.pfsense"]

  # Replace pfSense runtime configuration before installing REST API and before creating the API user.
  #
  # var.template_key=pfsense_template_01 -> files/pfsense_template_01_config.xml
  # var.template_key=pfsense_template_02 -> files/pfsense_template_02_config.xml
  provisioner "file" {
    source      = "files/${var.template_key}_config.xml"
    destination = "/root/config.xml"
  }

  provisioner "shell" {
    inline = [
      "set -eu",
      "echo 'Replacing /cf/conf/config.xml with files/${var.template_key}_config.xml'",
      "test -s /root/config.xml",
      "grep -q '<pfsense>' /root/config.xml",
      "grep -q '<tracker>1772011905</tracker>' /root/config.xml",
      "cp -f /root/config.xml /cf/conf/config.xml",
      "chmod 600 /cf/conf/config.xml",
      "chown root:wheel /cf/conf/config.xml",
      "rm -f /tmp/config.cache",
      "sync",
      "grep -q '<tracker>1772011905</tracker>' /cf/conf/config.xml"
    ]
  }

  provisioner "shell" {
    inline = [
      "set -eu",
      "echo 'Installing pfSense REST API package after config.xml replacement'",
      "pkg-static add -f https://github.com/pfrest/pfSense-pkg-RESTAPI/releases/latest/download/pfSense-2.8.1-pkg-RESTAPI.pkg",
      "pkg-static info -e pfSense-pkg-RESTAPI",
      "test -d /usr/local/pkg/RESTAPI",
      "pfsense-restapi status || true",
      "sync"
    ]
  }

  provisioner "file" {
    source      = local.create_api_user_path
    destination = local.remote_create_api_user
  }

  provisioner "shell" {
    environment_vars = [
      "PFSENSE_API_USER=${var.pfsense_api_user}",
      "PFSENSE_API_PASS=${local.pfsense_api_password}",
      "PFSENSE_API_PRIVS=page-all"
    ]

    inline = [
      "chmod 700 /root/create_apiuser.php",
      "chown root:wheel /root/create_apiuser.php",
      "/usr/local/bin/php /root/create_apiuser.php"
    ]
  }
}