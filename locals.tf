###############################################################
# Locals
###############################################################

locals {
  common_tags = {
    Environment = var.environment
    Project     = var.name
    Region      = var.region
    ManagedBy   = "Terraform"
    Owner       = "rp-infra-network"
  }
}
