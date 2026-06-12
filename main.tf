###############################################################
# Root main.tf — MCT Australia Stage Network Hub
# Region: ap-southeast-2 (Sydney)
# IPAM Pool: mct-au-network-pool (10.220.192.0/19)
###############################################################

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}

###############################################################
# IPAM
# Looks up the existing IPAM pool by ID so we can pass the
# pool ID to each VPC. Each VPC self-allocates its own CIDR
# directly from the pool via ipv4_ipam_pool_id on aws_vpc.
# No separate allocation resources — that caused double-
# allocation and CIDR mismatch errors.
###############################################################
module "ipam" {
  source = "./modules/ipam"

  region       = var.region
  environment  = var.environment
  ipam_pool_id = var.ipam_pool_id
}

###############################################################
# Transit Gateway
###############################################################
module "tgw" {
  source = "./modules/tgw"

  name        = var.name
  environment = var.environment
  asn         = var.tgw_asn
  tags        = local.common_tags
}

###############################################################
# Inspect VPC — /22 allocated from IPAM
# Subnets carved from aws_vpc.this.cidr_block inside module
###############################################################
module "inspect_vpc" {
  source = "./modules/inspect_vpc"

  name        = var.name
  environment = var.environment
  azs         = var.azs

  # IPAM allocates the VPC CIDR — no hardcoded vpc_cidr needed
  ipam_pool_id        = module.ipam.ipam_pool_id
  ipam_netmask_length = 22
  # vpc_cidr kept as placeholder; subnets use aws_vpc.this.cidr_block internally
  vpc_cidr = ""

  tgw_id         = module.tgw.tgw_id
  tgw_core_rt_id = module.tgw.core_route_table_id

  tags = local.common_tags
}

###############################################################
# Ingress VPC — /23 allocated from IPAM
###############################################################
module "ingress_vpc" {
  source = "./modules/ingress_vpc"

  name        = var.name
  environment = var.environment
  azs         = var.azs

  ipam_pool_id        = module.ipam.ipam_pool_id
  ipam_netmask_length = 23
  vpc_cidr            = ""

  tgw_id         = module.tgw.tgw_id
  tgw_core_rt_id = module.tgw.core_route_table_id

  gwlb_endpoint_service_name = module.inspect_vpc.gwlb_endpoint_service_name
  spoke_cidrs                = var.spoke_cidrs

  tags = local.common_tags
}

###############################################################
# Endpoints VPC — /23 allocated from IPAM
###############################################################
module "endpoints_vpc" {
  source = "./modules/endpoints_vpc"

  name        = var.name
  environment = var.environment
  azs         = var.azs

  ipam_pool_id        = module.ipam.ipam_pool_id
  ipam_netmask_length = 23
  vpc_cidr            = ""

  tgw_id          = module.tgw.tgw_id
  tgw_core_rt_id  = module.tgw.core_route_table_id
  tgw_spoke_rt_id = module.tgw.spoke_route_table_id

  allowed_cidrs = var.spoke_cidrs

  tags = local.common_tags
}

###############################################################
# TGW Route Table Entries
# VPC CIDRs come from actual VPC outputs (aws_vpc.this.cidr_block)
# not from IPAM module — ensures CIDRs match what was allocated
###############################################################
module "tgw_routes" {
  source = "./modules/tgw_routes"

  core_route_table_id  = module.tgw.core_route_table_id
  spoke_route_table_id = module.tgw.spoke_route_table_id

  inspect_attachment_id   = module.inspect_vpc.tgw_attachment_id
  ingress_attachment_id   = module.ingress_vpc.tgw_attachment_id
  endpoints_attachment_id = module.endpoints_vpc.tgw_attachment_id

  spoke_cidrs        = var.spoke_cidrs
  inspect_vpc_cidr   = module.inspect_vpc.vpc_cidr_block
  endpoints_vpc_cidr = module.endpoints_vpc.vpc_cidr_block
  ingress_vpc_cidr   = module.ingress_vpc.vpc_cidr_block

  tags = local.common_tags
}
