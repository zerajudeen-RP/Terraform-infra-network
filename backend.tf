###############################################################
# Backend — Terraform Cloud
###############################################################

terraform {
  cloud {
    organization = "RadPartners"       
    workspaces {
      name = "tf-aws-mct-infra-network"       
    }
  }
}
