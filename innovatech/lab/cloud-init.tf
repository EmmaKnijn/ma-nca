# Control Plane Cloud-Init Snippet
resource "null_resource" "proxmox_snippets_dir" { # make sure the /var/lib/vz/snippets actually exists on the host
  connection {
    type  = "ssh"
    host  = "192.168.106.9"
    user  = "root"
    agent = true
  }

  provisioner "remote-exec" {
    inline = [
      "mkdir -p /var/lib/vz/snippets",
      "pvesm set local --content backup,import,iso,vztmpl,snippets"

    ]
  }
} 

resource "proxmox_virtual_environment_file" "k8s_node_config" {
  for_each = local.k8s_nodes

  depends_on   = [null_resource.proxmox_snippets_dir]
  content_type = "snippets"
  datastore_id = "local"
  node_name    = "pve"

  source_raw {
    file_name = "${each.value.name}-init.yaml"
    data = templatefile("${path.module}/templates/k8s-node-init.yaml.tftpl", {
      hostname   = each.value.name
      password   = var.vm_user_password
      ssh_key    = var.vm_user_ssh_key
      k8s_version = local.k8s_version
    })
  }
}