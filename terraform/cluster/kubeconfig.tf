# =============================================================================
# KUBECONFIG RETRIEVAL
# Fetches kubeconfigs from primary and DR master nodes once cloud-init completes
# =============================================================================

resource "null_resource" "kubeconfig_primary" {
  depends_on = [hcloud_server.primary_master, hcloud_server.primary_workers]

  triggers = {
    master_ip = hcloud_server.primary_master.ipv4_address
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e
      until ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -i ${var.ssh_private_key_path} \
        root@${hcloud_server.primary_master.ipv4_address} 'cloud-init status --wait'; do sleep 10; done
      ssh -o StrictHostKeyChecking=no -i ${var.ssh_private_key_path} \
        root@${hcloud_server.primary_master.ipv4_address} 'cat /etc/rancher/k3s/k3s.yaml' \
        | sed "s/127.0.0.1/${hcloud_server.primary_master.ipv4_address}/g" \
        > ${path.module}/kubeconfig-primary.yaml
      kubectl config rename-context default ${var.primary_cluster_name} --kubeconfig=${path.module}/kubeconfig-primary.yaml
    EOT
  }
}

resource "null_resource" "kubeconfig_dr" {
  depends_on = [hcloud_server.dr_master, hcloud_server.dr_workers]

  triggers = {
    master_ip = hcloud_server.dr_master.ipv4_address
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e
      until ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -i ${var.ssh_private_key_path} \
        root@${hcloud_server.dr_master.ipv4_address} 'cloud-init status --wait'; do sleep 10; done
      ssh -o StrictHostKeyChecking=no -i ${var.ssh_private_key_path} \
        root@${hcloud_server.dr_master.ipv4_address} 'cat /etc/rancher/k3s/k3s.yaml' \
        | sed "s/127.0.0.1/${hcloud_server.dr_master.ipv4_address}/g" \
        > ${path.module}/kubeconfig-dr.yaml
      kubectl config rename-context default ${var.dr_cluster_name} --kubeconfig=${path.module}/kubeconfig-dr.yaml
    EOT
  }
}
