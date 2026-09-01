# kubeadm tokens require the format: [a-z0-9]{6}.[a-z0-9]{16}
resource "random_string" "token_id" {
  length  = 6
  special = false
  upper   = false
}

resource "random_string" "token_secret" {
  length  = 16
  special = false
  upper   = false
}

locals {
  control_plane_ip = "192.168.106.11"
  k8s_token        = "${random_string.token_id.result}.${random_string.token_secret.result}"
  k8s_version      = "v1.31" 

  k8s_nodes = {
    "node1" = {
      name = "ehv2-prod-k8s-0001"
      ip   = local.control_plane_ip
      role = "control-plane"
    }
    "node2" = {
      name = "ehv2-prod-k8s-0002"
      ip   = "192.168.106.12"
      role = "worker"
    }
    "node3" = {
      name = "ehv2-prod-k8s-0003"
      ip   = "192.168.106.13"
      role = "worker"
    }
  }
}

resource "proxmox_virtual_environment_vm" "k8s_cluster" {
  for_each  = local.k8s_nodes

  name      = each.value.name
  node_name = "pve"

  clone {
    vm_id = 9000
    full  = true
  }

  cpu {
    cores   = 12
    sockets = 1
    type    = "host"
  }

  memory {
    dedicated = 32768
  }

  disk {
    datastore_id = "local-lvm"
    interface    = "scsi0"
    size         = 20 # only 20gb as i dont have a ton of storage available on my proxmox host, but this can be increased as needed
    iothread     = true
    file_format  = "raw"
  }

  network_device {
    bridge   = "vmbr0"
    model    = "virtio"
    vlan_id  = 106
    firewall = false
  }

  agent {
    enabled = true
  }

  initialization {
    ip_config {
      ipv4 {
        address = "${each.value.ip}/24"
        gateway = "192.168.106.1"
      }
    }

    dns {
      servers = ["1.1.1.1", "8.8.8.8"]
    }

    user_data_file_id = each.value.role == "control-plane" ? proxmox_virtual_environment_file.k8s_control_plane_config.id : proxmox_virtual_environment_file.k8s_worker_config.id
  }
}