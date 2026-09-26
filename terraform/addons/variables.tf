variable "hcloud_token" {
  description = "Hetzner Cloud API token"
  type        = string
  sensitive   = true
}

variable "primary_cluster_name" {
  description = "Name of the primary Kubernetes cluster"
  type        = string
  default     = "naip-primary-k8s"
}

variable "dr_cluster_name" {
  description = "Name of the DR Kubernetes cluster"
  type        = string
  default     = "naip-dr-k8s"
}

variable "primary_location" {
  description = "Hetzner datacenter location for primary cluster (used by ingress-nginx LB)"
  type        = string
  default     = "nbg1"
}

variable "dr_location" {
  description = "Hetzner datacenter location for DR cluster (used by ingress-nginx LB)"
  type        = string
  default     = "hel1"
}

variable "primary_network_name" {
  description = "Name of primary cluster private network (defaults to <primary_cluster_name>-network)"
  type        = string
  default     = ""
}

variable "dr_network_name" {
  description = "Name of DR cluster private network (defaults to <dr_cluster_name>-network)"
  type        = string
  default     = ""
}

variable "kubeconfig_primary_path" {
  description = "Path to primary cluster kubeconfig"
  type        = string
  default     = "../cluster/kubeconfig-primary.yaml"
}

variable "kubeconfig_dr_path" {
  description = "Path to DR cluster kubeconfig"
  type        = string
  default     = "../cluster/kubeconfig-dr.yaml"
}

# -----------------------------------------------------------------------------
# Shared cluster variables (declared to allow sharing terraform.tfvars cleanly)
# -----------------------------------------------------------------------------

variable "node_type" {
  description = "Hetzner server type (cluster-level, ignored by addons)"
  type        = string
  default     = null
}

variable "node_count" {
  description = "Number of worker nodes (cluster-level, ignored by addons)"
  type        = number
  default     = null
}

variable "k8s_version" {
  description = "Kubernetes version (cluster-level, ignored by addons)"
  type        = string
  default     = null
}

variable "ssh_public_key" {
  description = "SSH public key (cluster-level, ignored by addons)"
  type        = string
  default     = null
}

variable "ssh_private_key_path" {
  description = "SSH private key path (cluster-level, ignored by addons)"
  type        = string
  default     = null
}

variable "network_zone" {
  description = "Hetzner network zone (cluster-level, ignored by addons)"
  type        = string
  default     = null
}
