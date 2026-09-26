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

variable "node_type" {
  description = "Hetzner server type for cluster nodes"
  type        = string
  default     = "cpx21" # 3 vCPU, 4 GB RAM
  # Alternatives: cpx31 (4 vCPU, 8 GB), cpx41 (8 vCPU, 16 GB)
}

variable "node_count" {
  description = "Number of worker nodes per cluster"
  type        = number
  default     = 3
}

variable "primary_location" {
  description = "Hetzner datacenter location for primary cluster"
  type        = string
  default     = "nbg1" # Nuremberg, Germany
}

variable "dr_location" {
  description = "Hetzner datacenter location for DR cluster"
  type        = string
  default     = "hel1" # Helsinki, Finland
}

variable "k8s_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.28" # Adjust to latest stable available in Hetzner
}

variable "ssh_public_key" {
  description = "SSH public key for cluster access"
  type        = string
  default     = "" # Will use default SSH key if empty
}

variable "ssh_private_key_path" {
  description = "Path to the private key matching ssh_public_key, used to fetch kubeconfigs and install cluster add-ons over SSH"
  type        = string
  default     = "~/.ssh/id_rsa"
}

variable "network_zone" {
  description = "Hetzner network zone"
  type        = string
  default     = "eu-central"
}
