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
├── terraform/
│   ├── cluster/            # Steps 1-2: clusters, network, firewall, LB, kubeconfig retrieval
│   │   ├── main.tf         # Servers, network, firewall, SSH key, load balancers
│   │   ├── kubeconfig.tf   # Kubeconfig retrieval over SSH
│   │   ├── cloud-init-master.yaml
│   │   ├── cloud-init-worker.yaml
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   ├── versions.tf
│   │   ├── backend.tf
│   │   └── terraform.tfvars.example
│   └── addons/             # Steps 3-4: cluster add-ons + Argo CD/Strimzi (Helm)
│       ├── main.tf         # Helm releases & Hetzner k8s secrets
│       ├── variables.tf
│       ├── outputs.tf
│       ├── versions.tf
│       ├── backend.tf
│       └── terraform.tfvars.example
└── kubernetes/
    ├── strimzi/            # Manual fallback docs (automated by addons module)
    └── argocd/             # Manual fallback docs (automated by addons module)
```

## Prerequisites

- Terraform >= 1.6.0
- kubectl >= 1.28
- helm >= 3.12
- Hetzner Cloud account with an API token
- SSH key pair for cluster access (public key in `terraform.tfvars`, private key path in `ssh_private_key_path`)

## Quick Start

### Step 1: Provision Clusters
```bash
cd terraform/cluster
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars: hcloud_token, ssh_public_key, ssh_private_key_path

terraform init
terraform plan
terraform apply
```

`terraform apply` provisions both clusters and retrieves and renames their kubeconfig
contexts (`kubeconfig-primary.yaml`, `kubeconfig-dr.yaml`).

### Step 2: Install Cluster Add-ons & Operators
```bash
cd ../addons
# terraform.tfvars can be symlinked to share tokens: ln -s ../cluster/terraform.tfvars .
terraform init
terraform plan
terraform apply
```

This installs the cluster add-ons (CCM, CSI, Ingress NGINX, cert-manager) plus Argo CD
and the Strimzi Kafka operator on both clusters. See the `next_steps` output for how
to merge kubeconfigs and hand off to the GitOps repo.

## Teardown

To tear down all provisioned infrastructure, resources must be destroyed in **reverse order** (**Add-ons first, then Cluster**) while the Kubernetes API is still reachable. This ensures that dynamic Hetzner Load Balancers (created by `ingress-nginx` via CCM) and Volumes (CSI) are cleanly deprovisioned before cluster servers and networks are removed.

### Using Make (Recommended)
From the `terraform/` directory:
```bash
cd terraform
make teardown
```
Or step-by-step:
```bash
make addons-destroy    # Step 1: Deletes Helm releases & dynamic Hetzner LBs/Volumes
make cluster-destroy   # Step 2: Deletes VMs, networks, firewalls, and base LB
```

### Manual Teardown
1. **Destroy Add-ons & Operators:**
   ```bash
   cd terraform/addons
   terraform destroy
   ```
2. **Destroy Cluster Infrastructure:**
   ```bash
   cd ../cluster
   terraform destroy
   ```
3. **(Optional) Clean up local kubeconfigs:**
   ```bash
   rm -f terraform/cluster/kubeconfig-primary.yaml terraform/cluster/kubeconfig-dr.yaml
   ```

## Local State

The default backend is local (`terraform.tfstate`). See `backend.tf` for
Terraform Cloud or Hetzner Object Storage (S3-compatible) alternatives.
