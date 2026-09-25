# =============================================================================
# KUBECONFIG RETRIEVAL (feeds the kubernetes/helm providers below)
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

# =============================================================================
# PROVIDERS (one aliased pair per cluster, pointed at the fetched kubeconfigs)
# =============================================================================

provider "kubernetes" {
  alias       = "primary"
  config_path = "${path.module}/kubeconfig-primary.yaml"
}

provider "helm" {
  alias = "primary"
  kubernetes {
    config_path = "${path.module}/kubeconfig-primary.yaml"
  }
}

provider "kubernetes" {
  alias       = "dr"
  config_path = "${path.module}/kubeconfig-dr.yaml"
}

provider "helm" {
  alias = "dr"
  kubernetes {
    config_path = "${path.module}/kubeconfig-dr.yaml"
  }
}

# =============================================================================
# HCLOUD CREDENTIALS SECRET (required by hcloud-ccm and hcloud-csi)
# =============================================================================

resource "kubernetes_secret" "hcloud_primary" {
  provider   = kubernetes.primary
  depends_on = [null_resource.kubeconfig_primary]

  metadata {
    name      = "hcloud"
    namespace = "kube-system"
  }

  data = {
    token   = var.hcloud_token
    network = hcloud_network.primary.name
  }
}

resource "kubernetes_secret" "hcloud_dr" {
  provider   = kubernetes.dr
  depends_on = [null_resource.kubeconfig_dr]

  metadata {
    name      = "hcloud"
    namespace = "kube-system"
  }

  data = {
    token   = var.hcloud_token
    network = hcloud_network.dr.name
  }
}

# =============================================================================
# STEP 3: CLUSTER ADD-ONS - PRIMARY
# =============================================================================

resource "helm_release" "hcloud_ccm_primary" {
  provider   = helm.primary
  depends_on = [kubernetes_secret.hcloud_primary]

  name       = "hcloud-cloud-controller-manager"
  repository = "https://charts.hetzner.cloud"
  chart      = "hcloud-cloud-controller-manager"
  namespace  = "kube-system"
  version    = "1.20.0"

  set {
    name  = "networking.enabled"
    value = "true"
  }
}

resource "helm_release" "hcloud_csi_primary" {
  provider   = helm.primary
  depends_on = [kubernetes_secret.hcloud_primary]

  name       = "hcloud-csi"
  repository = "https://charts.hetzner.cloud"
  chart      = "hcloud-csi"
  namespace  = "kube-system"
  version    = "2.9.0"
}

resource "helm_release" "ingress_nginx_primary" {
  provider         = helm.primary
  depends_on       = [helm_release.hcloud_ccm_primary]
  name             = "ingress-nginx"
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  namespace        = "ingress-nginx"
  create_namespace = true
  version          = "4.11.3"

  set {
    name  = "controller.service.type"
    value = "LoadBalancer"
  }

  set {
    name  = "controller.service.annotations.load-balancer\\.hetzner\\.cloud/location"
    value = var.primary_location
  }
}

resource "helm_release" "cert_manager_primary" {
  provider         = helm.primary
  depends_on       = [null_resource.kubeconfig_primary]
  name             = "cert-manager"
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  namespace        = "cert-manager"
  create_namespace = true
  version          = "v1.16.2"

  set {
    name  = "installCRDs"
    value = "true"
  }
}

# =============================================================================
# STEP 4: ARGO CD + STRIMZI OPERATOR - PRIMARY
# =============================================================================

resource "helm_release" "strimzi_primary" {
  provider         = helm.primary
  depends_on       = [null_resource.kubeconfig_primary]
  name             = "strimzi-kafka-operator"
  repository       = "https://strimzi.io/charts/"
  chart            = "strimzi-kafka-operator"
  namespace        = "kafka"
  create_namespace = true
  version          = "0.44.0"
}

resource "helm_release" "argocd_primary" {
  provider         = helm.primary
  depends_on       = [null_resource.kubeconfig_primary]
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  namespace        = "argocd"
  create_namespace = true
  version          = "7.7.11"
}

# =============================================================================
# STEP 3: CLUSTER ADD-ONS - DR
# =============================================================================

resource "helm_release" "hcloud_ccm_dr" {
  provider   = helm.dr
  depends_on = [kubernetes_secret.hcloud_dr]

  name       = "hcloud-cloud-controller-manager"
  repository = "https://charts.hetzner.cloud"
  chart      = "hcloud-cloud-controller-manager"
  namespace  = "kube-system"
  version    = "1.20.0"

  set {
    name  = "networking.enabled"
    value = "true"
  }
}

resource "helm_release" "hcloud_csi_dr" {
  provider   = helm.dr
  depends_on = [kubernetes_secret.hcloud_dr]

  name       = "hcloud-csi"
  repository = "https://charts.hetzner.cloud"
  chart      = "hcloud-csi"
  namespace  = "kube-system"
  version    = "2.9.0"
}

resource "helm_release" "ingress_nginx_dr" {
  provider         = helm.dr
  depends_on       = [helm_release.hcloud_ccm_dr]
  name             = "ingress-nginx"
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  namespace        = "ingress-nginx"
  create_namespace = true
  version          = "4.11.3"

  set {
    name  = "controller.service.type"
    value = "LoadBalancer"
  }

  set {
    name  = "controller.service.annotations.load-balancer\\.hetzner\\.cloud/location"
    value = var.dr_location
  }
}

resource "helm_release" "cert_manager_dr" {
  provider         = helm.dr
  depends_on       = [null_resource.kubeconfig_dr]
  name             = "cert-manager"
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  namespace        = "cert-manager"
  create_namespace = true
  version          = "v1.16.2"

  set {
    name  = "installCRDs"
    value = "true"
  }
}

# =============================================================================
# STEP 4: ARGO CD + STRIMZI OPERATOR - DR
# =============================================================================

resource "helm_release" "strimzi_dr" {
  provider         = helm.dr
  depends_on       = [null_resource.kubeconfig_dr]
  name             = "strimzi-kafka-operator"
  repository       = "https://strimzi.io/charts/"
  chart            = "strimzi-kafka-operator"
  namespace        = "kafka"
  create_namespace = true
  version          = "0.44.0"
}

resource "helm_release" "argocd_dr" {
  provider         = helm.dr
  depends_on       = [null_resource.kubeconfig_dr]
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  namespace        = "argocd"
  create_namespace = true
  version          = "7.7.11"
}
