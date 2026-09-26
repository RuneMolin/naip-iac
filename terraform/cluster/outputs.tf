output "primary_cluster_name" {
  description = "Name of the primary Kubernetes cluster"
  value       = var.primary_cluster_name
}

output "dr_cluster_name" {
  description = "Name of the DR Kubernetes cluster"
  value       = var.dr_cluster_name
}

output "primary_master_ip" {
  description = "Public IP of primary cluster master node"
  value       = hcloud_server.primary_master.ipv4_address
}

output "dr_master_ip" {
  description = "Public IP of DR cluster master node"
  value       = hcloud_server.dr_master.ipv4_address
}

output "primary_worker_ips" {
  description = "Public IPs of primary cluster worker nodes"
  value       = hcloud_server.primary_workers[*].ipv4_address
}

output "dr_worker_ips" {
  description = "Public IPs of DR cluster worker nodes"
  value       = hcloud_server.dr_workers[*].ipv4_address
}

output "primary_lb_ip" {
  description = "IP address of primary cluster load balancer"
  value       = hcloud_load_balancer.primary.ipv4
}

output "dr_lb_ip" {
  description = "IP address of DR cluster load balancer"
  value       = hcloud_load_balancer.dr.ipv4
}

output "primary_network_id" {
  description = "ID of primary cluster private network"
  value       = hcloud_network.primary.id
}

output "dr_network_id" {
  description = "ID of DR cluster private network"
  value       = hcloud_network.dr.id
}

output "primary_network_name" {
  description = "Name of primary cluster private network"
  value       = hcloud_network.primary.name
}

output "dr_network_name" {
  description = "Name of DR cluster private network"
  value       = hcloud_network.dr.name
}

output "kubeconfig_primary_path" {
  description = "Path to primary cluster kubeconfig"
  value       = "${path.module}/kubeconfig-primary.yaml"
}

output "kubeconfig_dr_path" {
  description = "Path to DR cluster kubeconfig"
  value       = "${path.module}/kubeconfig-dr.yaml"
}

output "next_steps" {
  description = "Next steps to deploy add-ons and access the clusters"
  value = <<-EOT

  ============================================================
  CLUSTERS PROVISIONED SUCCESSFULLY (Steps 1 & 2)
  ============================================================

  Primary Cluster: ${var.primary_cluster_name}
  Master IP: ${hcloud_server.primary_master.ipv4_address}
  Location: ${var.primary_location}
  Kubeconfig: ${path.module}/kubeconfig-primary.yaml

  DR Cluster: ${var.dr_cluster_name}
  Master IP: ${hcloud_server.dr_master.ipv4_address}
  Location: ${var.dr_location}
  Kubeconfig: ${path.module}/kubeconfig-dr.yaml

  ============================================================
  NEXT STEPS
  ============================================================

  1. Deploy cluster add-ons (CCM, CSI, ingress-nginx, cert-manager, Argo CD, Strimzi):
     cd ../addons
     cp terraform.tfvars.example terraform.tfvars  # or symlink: ln -s ../cluster/terraform.tfvars .
     terraform init
     terraform apply

  2. Merge kubeconfigs for local kubectl access:
     export KUBECONFIG=${path.module}/kubeconfig-primary.yaml:${path.module}/kubeconfig-dr.yaml
     kubectl config view --flatten > ~/.kube/config

  3. Hand off to GitOps (step 5):
     Once Argo CD is confirmed ready, apply the relevant bootstrap manifest:
       kubectl apply -f bootstrap/sandbox.yaml --kubeconfig=${path.module}/kubeconfig-primary.yaml

  ============================================================
  EOT
}
