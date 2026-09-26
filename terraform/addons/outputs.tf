output "addons_installed" {
  description = "List of add-ons installed across clusters"
  value = [
    "hcloud-cloud-controller-manager",
    "hcloud-csi",
    "ingress-nginx",
    "cert-manager",
    "strimzi-kafka-operator",
    "argo-cd"
  ]
}

output "next_steps" {
  description = "Next steps after add-on installation"
  value = <<-EOT

  ============================================================
  ADD-ONS INSTALLED SUCCESSFULLY (Steps 3 & 4)
  ============================================================

  Installed on both Primary (${var.primary_cluster_name}) and DR (${var.dr_cluster_name}):
  - Hetzner Cloud Controller Manager (hcloud-ccm)
  - Hetzner CSI Driver (hcloud-csi)
  - Ingress NGINX (LoadBalancer)
  - Cert-Manager
  - Strimzi Kafka Operator
  - Argo CD

  ============================================================
  NEXT STEPS (Step 5: GitOps Handoff)
  ============================================================

  1. Verify access to clusters:
     export KUBECONFIG=${var.kubeconfig_primary_path}:${var.kubeconfig_dr_path}
     kubectl config view --flatten > ~/.kube/config
     kubectl get pods -A

  2. Hand off to GitOps:
     Clone github.com/RuneMolin/naip-argo-demo (or your fork) and apply
     the relevant bootstrap manifest once Argo CD is confirmed ready:
       kubectl apply -f bootstrap/sandbox.yaml
     From then on Argo CD self-manages wrapper/ -> solution/ -> kafka/.

  ============================================================
  EOT
}
