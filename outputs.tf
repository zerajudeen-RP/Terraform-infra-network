###############################################################
# Root Outputs
###############################################################

output "ipam_pool_id" {
  description = "IPAM pool ID (mct-au-network-pool)"
  value       = module.ipam.ipam_pool_id
}

# VPC CIDRs come from the actual allocated values on each VPC
# Run 'terraform output' after apply to see what IPAM assigned
output "inspect_vpc_cidr" {
  description = "Actual IPAM-allocated CIDR for Inspect VPC"
  value       = module.inspect_vpc.vpc_cidr_block
}

output "ingress_vpc_cidr" {
  description = "Actual IPAM-allocated CIDR for Ingress VPC"
  value       = module.ingress_vpc.vpc_cidr_block
}

output "endpoints_vpc_cidr" {
  description = "Actual IPAM-allocated CIDR for Endpoints VPC"
  value       = module.endpoints_vpc.vpc_cidr_block
}

output "tgw_id" {
  description = "Transit Gateway ID"
  value       = module.tgw.tgw_id
}

output "tgw_core_route_table_id" {
  description = "TGW core route table ID"
  value       = module.tgw.core_route_table_id
}

output "tgw_spoke_route_table_id" {
  description = "TGW spoke route table ID"
  value       = module.tgw.spoke_route_table_id
}

output "inspect_vpc_id" {
  description = "Inspect VPC ID"
  value       = module.inspect_vpc.vpc_id
}

output "inspect_tgw_attachment_id" {
  description = "Inspect VPC TGW attachment ID"
  value       = module.inspect_vpc.tgw_attachment_id
}

output "gwlb_endpoint_service_name" {
  description = "GWLB endpoint service name (used by ingress VPC GWLBe)"
  value       = module.inspect_vpc.gwlb_endpoint_service_name
}

output "ingress_vpc_id" {
  description = "Ingress VPC ID"
  value       = module.ingress_vpc.vpc_id
}

output "ingress_tgw_attachment_id" {
  description = "Ingress VPC TGW attachment ID"
  value       = module.ingress_vpc.tgw_attachment_id
}

output "ingress_nlb_subnet_ids" {
  description = "NLB subnet IDs in Ingress VPC"
  value       = module.ingress_vpc.nlb_subnet_ids
}

output "ingress_alb_subnet_ids" {
  description = "ALB subnet IDs in Ingress VPC"
  value       = module.ingress_vpc.alb_subnet_ids
}

output "endpoints_vpc_id" {
  description = "Endpoints VPC ID"
  value       = module.endpoints_vpc.vpc_id
}

output "endpoints_tgw_attachment_id" {
  description = "Endpoints VPC TGW attachment ID"
  value       = module.endpoints_vpc.tgw_attachment_id
}

output "endpoints_subnet_ids" {
  description = "Interface endpoint subnet IDs"
  value       = module.endpoints_vpc.endpoint_subnet_ids
}
