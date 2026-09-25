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

# Instructions for accessing clusters
output "next_steps" {
  description = "Next steps to access the clusters"
  value = <<-EOT
  
  ============================================================
  CLUSTERS PROVISIONED SUCCESSFULLY
  ============================================================
  
  Primary Cluster: ${var.primary_cluster_name}
  Master IP: ${hcloud_server.primary_master.ipv4_address}
  Location: ${var.primary_location}
  
  DR Cluster: ${var.dr_cluster_name}
  Master IP: ${hcloud_server.dr_master.ipv4_address}
  Location: ${var.dr_location}
  
  ============================================================
  NEXT STEPS
  ============================================================
  
  Kubeconfigs (kubeconfig-primary.yaml, kubeconfig-dr.yaml) were retrieved
  automatically, and cluster add-ons (hcloud-cloud-controller-manager,
  hcloud-csi, ingress-nginx, cert-manager) plus Argo CD and the Strimzi
  Kafka operator were installed automatically by addons.tf (steps 1-4).
  
  1. Merge kubeconfigs for local kubectl access:
     export KUBECONFIG=${path.module}/kubeconfig-primary.yaml:${path.module}/kubeconfig-dr.yaml
     kubectl config view --flatten > ~/.kube/config
  
  2. Verify access:
     kubectl config use-context ${var.primary_cluster_name}
     kubectl get nodes
     kubectl config use-context ${var.dr_cluster_name}
     kubectl get nodes
  
  3. This repo's job ends here (step 4). Hand off to GitOps (step 5):
     clone github.com/RuneMolin/naip-argo-demo (or your fork) and apply
     the relevant bootstrap manifest once Argo CD is confirmed ready:
       kubectl apply -f bootstrap/sandbox.yaml
     From then on Argo CD self-manages wrapper/ -> solution/ -> kafka/.
  
  ============================================================
  EOT
}
