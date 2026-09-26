# Terraform Backend Configuration - Add-ons
#
# Uncomment ONE of the options below:

# =============================================================================
# OPTION 1: Terraform Cloud (Recommended for teams, free tier available)
# =============================================================================
# terraform {
#   cloud {
#     organization = "YOUR_ORG_NAME"
#     
#     workspaces {
#       name = "naip-iac-addons"
#     }
#   }
# }

# =============================================================================
# OPTION 2: Local State (Simple, for single-user development)
# =============================================================================
# Comment out this block if using Terraform Cloud
terraform {
  backend "local" {
    path = "terraform.tfstate"
  }
}

# =============================================================================
# OPTION 3: Hetzner Object Storage (S3-compatible, cost-effective)
# =============================================================================
# terraform {
#   backend "s3" {
#     endpoints = {
#       s3 = "https://fsn1.your-objectstorage.com"
#     }
#     bucket                      = "naip-terraform-state"
#     key                         = "addons/terraform.tfstate"
#     region                      = "us-east-1" # Required but ignored
#     skip_credentials_validation = true
#     skip_metadata_api_check     = true
#     skip_region_validation      = true
#     skip_requesting_account_id  = true
#     use_path_style              = true
#   }
# }
