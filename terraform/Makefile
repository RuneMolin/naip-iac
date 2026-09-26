.PHONY: help cluster-init cluster-plan cluster-apply addons-init addons-plan addons-apply

help:
	@echo "NAIP IaC Terraform Commands:"
	@echo "  make cluster-init   - Initialize cluster module"
	@echo "  make cluster-plan   - Plan cluster infrastructure (Steps 1 & 2)"
	@echo "  make cluster-apply  - Apply cluster infrastructure and fetch kubeconfigs"
	@echo "  make addons-init    - Initialize add-ons module"
	@echo "  make addons-plan    - Plan add-ons (Steps 3 & 4)"
	@echo "  make addons-apply   - Apply add-ons (CCM, CSI, Ingress, cert-manager, Argo CD, Strimzi)"

cluster-init:
	cd cluster && terraform init

cluster-plan:
	cd cluster && terraform plan

cluster-apply:
	cd cluster && terraform apply

addons-init:
	cd addons && terraform init

addons-plan:
	cd addons && terraform plan

addons-apply:
	cd addons && terraform apply
