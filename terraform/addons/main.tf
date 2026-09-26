# =============================================================================
# LOCALS & PROVIDERS
# Reads kubeconfig from cluster module; falls back to dummy-kubeconfig.yaml
# during initial terraform plan before the cluster is applied.
# =============================================================================

locals {
  kubeconfig_primary = fileexists(var.kubeconfig_primary_path) ? var.kubeconfig_primary_path : "${path.module}/dummy-kubeconfig.yaml"
  kubeconfig_dr      = fileexists(var.kubeconfig_dr_path) ? var.kubeconfig_dr_path : "${path.module}/dummy-kubeconfig.yaml"

  primary_network = var.primary_network_name != "" ? var.primary_network_name : "${var.primary_cluster_name}-network"
  dr_network      = var.dr_network_name != "" ? var.dr_network_name : "${var.dr_cluster_name}-network"
}

provider "kubernetes" {
  alias       = "primary"
  config_path = local.kubeconfig_primary
}

provider "helm" {
  alias = "primary"
  kubernetes {
    config_path = local.kubeconfig_primary
  }
}

provider "kubernetes" {
  alias       = "dr"
  config_path = local.kubeconfig_dr
}

provider "helm" {
  alias = "dr"
  kubernetes {
    config_path = local.kubeconfig_dr
  }
}

# =============================================================================
# HCLOUD CREDENTIALS SECRET (required by hcloud-ccm and hcloud-csi)
# =============================================================================

resource "kubernetes_secret" "hcloud_primary" {
  provider = kubernetes.primary

  metadata {
    name      = "hcloud"
    namespace = "kube-system"
  }

  data = {
    token   = var.hcloud_token
    network = local.primary_network
  }
}

resource "kubernetes_secret" "hcloud_dr" {
  provider = kubernetes.dr

  metadata {
    name      = "hcloud"
    namespace = "kube-system"
  }

  data = {
    token   = var.hcloud_token
    network = local.dr_network
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
  name             = "strimzi-kafka-operator"
  repository       = "https://strimzi.io/charts/"
  chart            = "strimzi-kafka-operator"
  namespace        = "kafka"
  create_namespace = true
  version          = "0.44.0"
}

resource "helm_release" "argocd_primary" {
  provider         = helm.primary
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
  name             = "strimzi-kafka-operator"
  repository       = "https://strimzi.io/charts/"
  chart            = "strimzi-kafka-operator"
  namespace        = "kafka"
  create_namespace = true
  version          = "0.44.0"
}

resource "helm_release" "argocd_dr" {
  provider         = helm.dr
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  namespace        = "argocd"
  create_namespace = true
  version          = "7.7.11"
}
