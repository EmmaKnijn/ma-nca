# Control Plane Cloud-Init Snippet
resource "proxmox_virtual_environment_file" "k8s_control_plane_config" {
  content_type = "snippets"
  datastore_id = "local"
  node_name    = "pve"

  source_raw {
    file_name = "k8s-control-plane-init.yaml"
    data      = <<-EOF
      #cloud-config
      package_update: true
      packages:
        - apt-transport-https
        - ca-certificates
        - curl
        - gnupg
        - containerd

      write_files:
        - path: /etc/modules-load.d/k8s.conf
          content: |
            overlay
            br_netfilter
        - path: /etc/sysctl.d/k8s.conf
          content: |
            net.bridge.bridge-nf-call-iptables  = 1
            net.bridge.bridge-nf-call-ip6tables = 1
            net.ipv4.ip_forward                 = 1

      runcmd:
        - swapoff -a
        - sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab
        - modprobe overlay
        - modprobe br_netfilter
        - sysctl --system
        - mkdir -p /etc/containerd
        - containerd config default | tee /etc/containerd/config.toml
        - sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml
        - systemctl restart containerd
        - mkdir -p -m 755 /etc/apt/keyrings
        - curl -fsSL https://pkgs.k8s.io/core:/stable:/${local.k8s_version}/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
        - echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/${local.k8s_version}/deb/ /' > /etc/apt/sources.list.d/kubernetes.list
        - apt-get update
        - apt-get install -y kubelet kubeadm kubectl
        - apt-mark hold kubelet kubeadm kubectl
        - kubeadm init --apiserver-advertise-address=${local.control_plane_ip} --token "${local.k8s_token}" --token-ttl 0 --pod-network-cidr=10.244.0.0/16
        - mkdir -p /root/.kube
        - cp -i /etc/kubernetes/admin.conf /root/.kube/config
        - chown root:root /root/.kube/config
        - kubectl --kubeconfig=/etc/kubernetes/admin.conf apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
        - kubectl --kubeconfig=/etc/kubernetes/admin.conf taint nodes --all node-role.kubernetes.io/control-plane-
    EOF
  }
}

# Worker Node Cloud-Init Snippet
resource "proxmox_virtual_environment_file" "k8s_worker_config" {
  content_type = "snippets"
  datastore_id = "local"
  node_name    = "pve"

  source_raw {
    file_name = "k8s-worker-init.yaml"
    data      = <<-EOF
      #cloud-config
      package_update: true
      packages:
        - apt-transport-https
        - ca-certificates
        - curl
        - gnupg
        - containerd

      write_files:
        - path: /etc/modules-load.d/k8s.conf
          content: |
            overlay
            br_netfilter
        - path: /etc/sysctl.d/k8s.conf
          content: |
            net.bridge.bridge-nf-call-iptables  = 1
            net.bridge.bridge-nf-call-ip6tables = 1
            net.ipv4.ip_forward                 = 1

      runcmd:
        - swapoff -a
        - sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab
        - modprobe overlay
        - modprobe br_netfilter
        - sysctl --system
        - mkdir -p /etc/containerd
        - containerd config default | tee /etc/containerd/config.toml
        - sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml
        - systemctl restart containerd
        - mkdir -p -m 755 /etc/apt/keyrings
        - curl -fsSL https://pkgs.k8s.io/core:/stable:/${local.k8s_version}/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
        - echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/${local.k8s_version}/deb/ /' > /etc/apt/sources.list.d/kubernetes.list
        - apt-get update
        - apt-get install -y kubelet kubeadm
        - apt-mark hold kubelet kubeadm
        - |
          until curl -k -s "https://${local.control_plane_ip}:6443/livez" > /dev/null; do
            echo "Waiting for control plane API server..."
            sleep 5
          done
        - kubeadm join ${local.control_plane_ip}:6443 --token "${local.k8s_token}" --discovery-token-unsafe-skip-ca-verification
    EOF
  }
}