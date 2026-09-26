# Terraform Infrastructure & Add-ons

This directory is structured into two decoupled stages to eliminate provider race conditions and allow clean planning and provisioning:

```text
terraform/
├── cluster/     # Steps 1 & 2: Hetzner VMs, networks, firewall, LB, k3s bootstrap & kubeconfigs
└── addons/      # Steps 3 & 4: Helm charts (CCM, CSI, Ingress NGINX, cert-manager, Argo CD, Strimzi)
```

## Quick Start

### Step 1: Provision Cluster Infrastructure
```bash
cd cluster
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your Hetzner token and SSH keys

terraform init
terraform plan
terraform apply
```
This provisions both primary and DR clusters and automatically downloads `kubeconfig-primary.yaml` and `kubeconfig-dr.yaml` into `cluster/`.

### Step 2: Install Cluster Add-ons & Operators
```bash
cd ../addons
# terraform.tfvars can be symlinked to share tokens: ln -s ../cluster/terraform.tfvars .
terraform init
terraform plan
terraform apply
```
This installs the required cluster add-ons (CCM, CSI, Ingress, cert-manager) plus Argo CD and the Strimzi Kafka operator on both clusters.

### Step 3: GitOps Handoff
Once Argo CD is ready, hand off to the GitOps repository as described in `naip-argo-demo`.

## Teardown

Always destroy infrastructure in **reverse order** (**Add-ons first, then Cluster**) while the clusters are still running so that Hetzner Cloud Controller Manager (`hcloud-ccm`) and CSI can cleanly delete external Load Balancers and attached Volumes:

### Using the Makefile
```bash
make teardown
```
Or step-by-step:
```bash
make addons-destroy    # Step 1: Destroys Helm charts and dynamic Hetzner LBs
make cluster-destroy   # Step 2: Destroys VMs, networks, firewalls, and control-plane LBs
```

### Manual Teardown
```bash
# 1. Destroy Helm releases and dynamic Hetzner resources
cd addons
terraform destroy

# 2. Destroy VMs, networks, firewalls, and base Load Balancers
cd ../cluster
terraform destroy

# 3. (Optional) Remove local kubeconfigs
rm -f kubeconfig-primary.yaml kubeconfig-dr.yaml
```

