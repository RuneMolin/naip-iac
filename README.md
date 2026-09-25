# NAIP IaC

Infrastructure as Code for NAIP: provisions the Hetzner Cloud Kubernetes clusters
(Primary + DR) and everything needed before GitOps takes over.

This repo covers steps 1-4 of the prerequisites described in
[naip-argo-demo](https://github.com/RuneMolin/naip-argo-demo):

1. **Terraform** - servers, private network, firewall rules, SSH key, load balancer.
2. **Cluster bootstrap** - k3s install, fused into step 1 via cloud-init user_data.
3. **Cluster add-ons** - `hcloud-cloud-controller-manager`, `hcloud-csi`,
   `ingress-nginx` (as a Hetzner LoadBalancer), and `cert-manager`.
4. **Argo CD + Strimzi Kafka operator** install.

Step 5 (the GitOps app-of-apps tree) lives in a separate repo,
[naip-argo-demo](https://github.com/RuneMolin/naip-argo-demo) (or your fork/copy of it) -
once this repo finishes step 4, apply that repo's `bootstrap/<env>.yaml` once and
Argo CD self-manages everything from there.

## Structure

```
.
├── terraform/              # Steps 1-4: clusters, kubeconfig retrieval, add-ons, Argo CD/Strimzi
│   ├── main.tf             # Servers, network, firewall, SSH key, load balancers
│   ├── addons.tf           # Kubeconfig retrieval + cluster add-ons + Argo CD/Strimzi (Helm)
│   ├── variables.tf
│   ├── outputs.tf
│   ├── versions.tf
│   ├── backend.tf
│   ├── cloud-init-master.yaml
│   ├── cloud-init-worker.yaml
│   └── terraform.tfvars.example
└── kubernetes/
    ├── strimzi/            # Manual fallback docs (automated by addons.tf by default)
    └── argocd/             # Manual fallback docs (automated by addons.tf by default)
```

## Prerequisites

- Terraform >= 1.6.0
- kubectl >= 1.28
- helm >= 3.12
- Hetzner Cloud account with an API token
- SSH key pair for cluster access (public key in `terraform.tfvars`, private key path in `ssh_private_key_path`)

## Quick Start

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars: hcloud_token, ssh_public_key, ssh_private_key_path

terraform init
terraform plan
terraform apply
```

`terraform apply` provisions both clusters, retrieves and renames their kubeconfig
contexts (`kubeconfig-primary.yaml`, `kubeconfig-dr.yaml`), and installs the cluster
add-ons, Argo CD, and the Strimzi Kafka operator on each cluster. See the
`next_steps` output for how to merge kubeconfigs and hand off to the GitOps repo.

## Local State

The default backend is local (`terraform.tfstate`). See `backend.tf` for
Terraform Cloud or Hetzner Object Storage (S3-compatible) alternatives.
