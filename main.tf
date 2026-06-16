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
# Inspect VPC — /22 with explicit CIDR
###############################################################
module "inspect_vpc" {
  source = "./modules/inspect_vpc"

  name        = var.name
  environment = var.environment
  azs         = var.azs

  vpc_cidr            = var.inspect_vpc_cidr
  ipam_pool_id        = var.ipam_pool_id
  ipam_netmask_length = 22

  tgw_id         = module.tgw.tgw_id
  tgw_core_rt_id = module.tgw.core_route_table_id

  tags = local.common_tags
}

###############################################################
# Ingress VPC — /21 with explicit CIDR, multi-environment
###############################################################
module "ingress_vpc" {
  source = "./modules/ingress_vpc"

  name        = var.name
  environment = var.environment
  azs         = var.azs

  ipam_pool_id        = var.ipam_pool_id
  ipam_netmask_length = 21
  spoke_cidrs         = var.spoke_cidrs

  tgw_id         = module.tgw.tgw_id
  tgw_core_rt_id = module.tgw.core_route_table_id

  # NFW endpoint IDs injected after ingress_nfw is created
  nfw_endpoint_ids = module.ingress_nfw.endpoint_ids

  tags = local.common_tags
}

###############################################################
# Ingress NFW — AWS Network Firewall in ingress VPC
# Deployed in the ingress VPC firewall subnets.
# Endpoint IDs are passed back to ingress_vpc for route tables.
###############################################################
module "ingress_nfw" {
  source = "./modules/ingress_nfw"

  name        = var.name
  environment = var.environment

  vpc_id     = module.ingress_vpc.vpc_id
  subnet_ids = module.ingress_vpc.firewall_subnet_ids
  azs        = var.azs

  enable_alert_logging = true
  enable_flow_logging  = true
  log_retention_days   = var.nfw_log_retention_days

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
  tgw_spoke_rt_id = module.tgw.spoke_stage_route_table_id

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
  spoke_route_table_ids = [
    module.tgw.spoke_stage_route_table_id,
    module.tgw.spoke_prod_route_table_id,
  ]

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
# TGW Spoke Attachments — cross-account RT association/propagation
#
# Workload accounts create TGW attachments but cannot touch the
# hub's route tables. This module runs in the hub account and
# associates + propagates each workload attachment to the spoke RT.
#
# Step 1: apply workload repo → get tgw_attachment_id from output
# Step 2: add that ID to spoke_attachment_ids in hub terraform.tfvars
# Step 3: re-apply hub repo
###############################################################
module "tgw_spoke_attachments" {
  source = "./modules/tgw_spoke_attachments"

  tgw_spoke_rt_id      = module.tgw.spoke_stage_route_table_id
  tgw_core_rt_id       = module.tgw.core_route_table_id
  spoke_attachment_ids = var.spoke_attachment_ids

  tags = local.common_tags
}

###############################################################
# RAM — Share TGW with workload accounts
###############################################################
module "ram" {
  source = "./modules/ram"

  name        = var.name
  environment = var.environment

  tgw_arn              = module.tgw.tgw_arn
  workload_account_ids = var.workload_account_ids

  allow_external_principals = var.ram_allow_external_principals

  tags = local.common_tags
}

###############################################################
# Network Firewall — deployed in Inspect VPC firewall subnets
#
# Endpoints are created per AZ. The inspect_vpc module's TGW
# subnet RTs initially point to GWLBe. After the NFW is created
# we replace those routes with NFW endpoint routes so all egress
# traffic flows: TGW subnet → NFW endpoint → firewall subnet
# → NAT GW → IGW → internet.
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
# Replace GWLBe routes in inspect VPC TGW subnet RTs with
# Network Firewall endpoint routes (one per AZ).
#
# The inspect_vpc module creates 0.0.0.0/0 → GWLBe by default.
# Those routes must be removed and replaced with NFW endpoints
# so egress traffic actually hits the firewall.
# We use replace_triggered_by to force recreation when endpoints change.
###############################################################
resource "aws_route" "inspect_tgw_to_nfw" {
  count                  = length(var.azs)
  route_table_id         = module.inspect_vpc.tgw_route_table_ids[count.index]
  destination_cidr_block = "0.0.0.0/0"
  vpc_endpoint_id        = module.network_firewall.endpoint_ids[count.index]

  # This conflicts with the GWLBe route in inspect_vpc module.
  # Run: terraform apply -replace=module.inspect_vpc.aws_route.tgw_to_gwlb
  # on first apply to remove the old route before this one is added.
  depends_on = [module.network_firewall, module.inspect_vpc]
}

###############################################################
# ALB + NLB + WAF — one per environment (demo, stage, prod)
###############################################################

# ─── DEMO ─────────────────────────────────────────────────────
module "alb_demo" {
  source = "./modules/alb"

  name        = var.name
  environment = "demo"

  vpc_id            = module.ingress_vpc.vpc_id
  subnet_ids        = module.ingress_vpc.alb_demo_subnet_ids
  security_group_id = module.ingress_vpc.alb_security_group_id

  certificate_arn        = var.alb_certificate_arn
  enable_https           = var.alb_certificate_arn != ""
  http_redirect_to_https = true
  ssl_policy             = var.alb_ssl_policy

  enable_deletion_protection = false
  idle_timeout               = var.alb_idle_timeout
  access_logs_bucket         = var.lb_access_logs_bucket
  access_logs_prefix         = "alb-demo"

  listener_rules = var.alb_listener_rules

  tags = local.common_tags
}

module "waf_demo" {
  source = "./modules/waf"

  name        = var.name
  environment = "demo"

  alb_arn            = module.alb_demo.alb_arn
  rate_limit         = var.waf_rate_limit
  enable_logging     = true
  log_retention_days = var.waf_log_retention_days

  tags = local.common_tags
}

module "nlb_demo" {
  source = "./modules/nlb"

  name        = var.name
  environment = "demo"

  vpc_id            = module.ingress_vpc.vpc_id
  subnet_ids        = module.ingress_vpc.nlb_demo_subnet_ids
  security_group_id = module.ingress_vpc.nlb_security_group_id

  alb_arn         = module.alb_demo.alb_arn
  alb_target_port = var.alb_certificate_arn != "" ? 443 : 80

  certificate_arn                  = var.nlb_certificate_arn
  enable_cross_zone_load_balancing = true
  enable_deletion_protection       = false
  access_logs_bucket               = var.lb_access_logs_bucket
  access_logs_prefix               = "nlb-demo"

  health_check_protocol            = "HTTP"
  health_check_interval            = 30
  health_check_healthy_threshold   = 3
  health_check_unhealthy_threshold = 3

  tags = local.common_tags
}

# ─── STAGE ────────────────────────────────────────────────────
module "alb_stage" {
  source = "./modules/alb"

  name        = var.name
  environment = "stage"

  vpc_id            = module.ingress_vpc.vpc_id
  subnet_ids        = module.ingress_vpc.alb_stage_subnet_ids
  security_group_id = module.ingress_vpc.alb_security_group_id

  certificate_arn        = var.alb_certificate_arn
  enable_https           = var.alb_certificate_arn != ""
  http_redirect_to_https = true
  ssl_policy             = var.alb_ssl_policy

  enable_deletion_protection = false
  idle_timeout               = var.alb_idle_timeout
  access_logs_bucket         = var.lb_access_logs_bucket
  access_logs_prefix         = "alb-stage"

  listener_rules = var.alb_listener_rules

  tags = local.common_tags
}

module "waf_stage" {
  source = "./modules/waf"

  name        = var.name
  environment = "stage"

  alb_arn            = module.alb_stage.alb_arn
  rate_limit         = var.waf_rate_limit
  enable_logging     = true
  log_retention_days = var.waf_log_retention_days

  tags = local.common_tags
}

module "nlb_stage" {
  source = "./modules/nlb"

  name        = var.name
  environment = "stage"

  vpc_id            = module.ingress_vpc.vpc_id
  subnet_ids        = module.ingress_vpc.nlb_stage_subnet_ids
  security_group_id = module.ingress_vpc.nlb_security_group_id

  alb_arn         = module.alb_stage.alb_arn
  alb_target_port = var.alb_certificate_arn != "" ? 443 : 80

  certificate_arn                  = var.nlb_certificate_arn
  enable_cross_zone_load_balancing = true
  enable_deletion_protection       = false
  access_logs_bucket               = var.lb_access_logs_bucket
  access_logs_prefix               = "nlb-stage"

  health_check_protocol            = "HTTP"
  health_check_interval            = 30
  health_check_healthy_threshold   = 3
  health_check_unhealthy_threshold = 3

  tags = local.common_tags
}

# ─── PROD ─────────────────────────────────────────────────────
module "alb_prod" {
  source = "./modules/alb"

  name        = var.name
  environment = "prod"

  vpc_id            = module.ingress_vpc.vpc_id
  subnet_ids        = module.ingress_vpc.alb_prod_subnet_ids
  security_group_id = module.ingress_vpc.alb_security_group_id

  certificate_arn        = var.alb_certificate_arn
  enable_https           = var.alb_certificate_arn != ""
  http_redirect_to_https = true
  ssl_policy             = var.alb_ssl_policy

  enable_deletion_protection = false
  idle_timeout               = var.alb_idle_timeout
  access_logs_bucket         = var.lb_access_logs_bucket
  access_logs_prefix         = "alb-prod"

  listener_rules = var.alb_listener_rules

  tags = local.common_tags
}

module "waf_prod" {
  source = "./modules/waf"

  name        = var.name
  environment = "prod"

  alb_arn            = module.alb_prod.alb_arn
  rate_limit         = var.waf_rate_limit
  enable_logging     = true
  log_retention_days = var.waf_log_retention_days

  tags = local.common_tags
}

module "nlb_prod" {
  source = "./modules/nlb"

  name        = var.name
  environment = "prod"

  vpc_id            = module.ingress_vpc.vpc_id
  subnet_ids        = module.ingress_vpc.nlb_prod_subnet_ids
  security_group_id = module.ingress_vpc.nlb_security_group_id

  alb_arn         = module.alb_prod.alb_arn
  alb_target_port = var.alb_certificate_arn != "" ? 443 : 80

  certificate_arn                  = var.nlb_certificate_arn
  enable_cross_zone_load_balancing = true
  enable_deletion_protection       = false
  access_logs_bucket               = var.lb_access_logs_bucket
  access_logs_prefix               = "nlb-prod"

  health_check_protocol            = "HTTP"
  health_check_interval            = 30
  health_check_healthy_threshold   = 3
  health_check_unhealthy_threshold = 3

  tags = local.common_tags
}

