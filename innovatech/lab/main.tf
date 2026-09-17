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
  control_plane_ip = "192.168.106.201"
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
      ip   = "192.168.106.202"
      role = "worker"
    }
    "node3" = {
      name = "ehv2-prod-k8s-0003"
      ip   = "192.168.106.203"
      role = "worker"
    }
  }
}

# Pull the Debian 13 (trixie) cloud image into Proxmox storage.
# Pinned to the specific dated snapshot (not "latest") to keep the build reproducible.
resource "proxmox_virtual_environment_download_file" "debian13_cloud_image" {
  content_type = "iso"
  datastore_id = "local"
  node_name    = "pve"
  url          = "https://cloud.debian.org/images/cloud/trixie/20250806-2196/debian-13-genericcloud-amd64-20250806-2196.qcow2"
  file_name    = "debian-13-genericcloud-amd64-20250806-2196.img" # renamed so Proxmox accepts it under the iso content type
  overwrite    = false
}

resource "proxmox_virtual_environment_vm" "debian13_template" {
  name      = "debian-13-cloudinit-template"
  node_name = "pve"
  vm_id     = 9000
  template  = true
  started   = false # templates should never boot themselves

  cpu {
    cores = 2
    type  = "host"
  }

  memory {
    dedicated = 2048
  }

  network_device {
    bridge = "vmbr0"
  }

  disk {
    datastore_id = "local-lvm"
    file_id      = proxmox_virtual_environment_download_file.debian13_cloud_image.id
    interface    = "scsi0"
    iothread     = true
    discard      = "on"
    size         = 20 # matches the disk size in k8s cluster clones
    file_format  = "raw"
  }

  # Required for Debian/Ubuntu cloud images: without a serial console configured,
  # they kernel-panic when the boot disk is resized on clone.
  serial_device {}

  scsi_hardware = "virtio-scsi-single"

  initialization {
    datastore_id = "local-lvm" # where the cloud-init drive itself is stored
    ip_config {
      ipv4 {
        address = "dhcp" # irrelevant on the template the clones override this
      }
    }
  }

  agent {
    enabled = true
  }

  operating_system {
    type = "l26"
  }

  lifecycle {
    ignore_changes = [
      network_device, # avoid template drift once clones exist
    ]
  }
}

resource "proxmox_virtual_environment_vm" "k8s_cluster" {
  for_each  = local.k8s_nodes

  name      = each.value.name
  node_name = "pve"

  clone {
    vm_id = proxmox_virtual_environment_vm.debian13_template.vm_id
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
    file_id      = proxmox_virtual_environment_download_file.debian13_cloud_image.id
    size         = 20 # only 20gb as i dont have a ton of storage available on my proxmox host, but this can be increased as needed
    iothread     = true
    file_format  = "raw"
  }

  disk {
    datastore_id = "iscsi-lvm"
    interface    = "scsi1"
    size         = 100 # simulates the persistent volume storage for the k8s cluster, but this can be increased as needed
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
    timeout = "10s"
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
    
  user_data_file_id = proxmox_virtual_environment_file.k8s_node_config[each.key].id
  }
}