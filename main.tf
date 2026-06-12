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

###############################################################
# Network Firewall — deployed in Inspect VPC firewall subnets
#
# Endpoints are created per AZ. The inspect_vpc module's firewall
# subnet route tables already point 0.0.0.0/0 → NAT GW, but for
# the TGW attach subnet RTs we wire traffic through the firewall
# endpoints instead of (or alongside) the GWLB endpoints.
# Both can coexist: GWLB handles N-S inbound via ingress VPC,
# Network Firewall handles E-W + egress in the inspect VPC.
###############################################################
module "network_firewall" {
  source = "./modules/network_firewall"

  name        = var.name
  environment = var.environment

  vpc_id     = module.inspect_vpc.vpc_id
  subnet_ids = module.inspect_vpc.firewall_subnet_ids
  azs        = var.azs

  home_net_cidrs  = concat(var.spoke_cidrs, ["10.220.192.0/19"])
  allowed_domains = var.nfw_allowed_domains

  enable_alert_logging = true
  enable_flow_logging  = true
  log_retention_days   = var.nfw_log_retention_days

  stateful_rule_order           = var.nfw_stateful_rule_order
  stateful_rule_group_capacity  = var.nfw_stateful_rule_group_capacity
  stateless_rule_group_capacity = var.nfw_stateless_rule_group_capacity

  tags = local.common_tags
}

###############################################################
# ALB — Internal, in Ingress VPC ALB subnets
###############################################################
module "alb" {
  source = "./modules/alb"

  name        = var.name
  environment = var.environment

  vpc_id            = module.ingress_vpc.vpc_id
  subnet_ids        = module.ingress_vpc.alb_subnet_ids
  security_group_id = module.ingress_vpc.alb_security_group_id

  certificate_arn        = var.alb_certificate_arn
  enable_https           = var.alb_certificate_arn != ""
  http_redirect_to_https = true
  ssl_policy             = var.alb_ssl_policy

  enable_deletion_protection = false
  idle_timeout               = var.alb_idle_timeout
  access_logs_bucket         = var.lb_access_logs_bucket
  access_logs_prefix         = "alb"

  listener_rules = var.alb_listener_rules

  tags = local.common_tags
}

###############################################################
# NLB — Internet-facing, in Ingress VPC NLB subnets
# Depends on ALB so it can register the ALB ARN as target.
# alb_target_port must match a port the ALB actually listens on.
# When no cert is provided, ALB only has HTTP/80, so use 80.
# When a cert is provided, ALB has HTTPS/443, so use 443.
###############################################################
module "nlb" {
  source = "./modules/nlb"

  name        = var.name
  environment = var.environment

  vpc_id            = module.ingress_vpc.vpc_id
  subnet_ids        = module.ingress_vpc.nlb_subnet_ids
  security_group_id = module.ingress_vpc.nlb_security_group_id

  alb_arn         = module.alb.alb_arn
  alb_target_port = var.alb_certificate_arn != "" ? 443 : 80

  certificate_arn                  = var.nlb_certificate_arn
  enable_cross_zone_load_balancing = true
  enable_deletion_protection       = false
  access_logs_bucket               = var.lb_access_logs_bucket
  access_logs_prefix               = "nlb"

  health_check_protocol            = "TCP"
  health_check_interval            = 30
  health_check_healthy_threshold   = 3
  health_check_unhealthy_threshold = 3

  tags = local.common_tags
}
