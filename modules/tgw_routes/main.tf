###############################################################
# Module: tgw_routes
# Populates TGW route table entries after all attachments exist
###############################################################

###############################################################
# SPOKE route table routes
# Used by workload/spoke VPCs
###############################################################

# Default route → inspect VPC (all internet traffic goes through inspection + NAT)
resource "aws_ec2_transit_gateway_route" "spoke_default_to_inspect" {
  destination_cidr_block         = "0.0.0.0/0"
  transit_gateway_attachment_id  = var.inspect_attachment_id
  transit_gateway_route_table_id = var.spoke_route_table_id
}

# Endpoints VPC CIDR → endpoints attachment (AWS service traffic)
resource "aws_ec2_transit_gateway_route" "spoke_to_endpoints" {
  destination_cidr_block         = var.endpoints_vpc_cidr
  transit_gateway_attachment_id  = var.endpoints_attachment_id
  transit_gateway_route_table_id = var.spoke_route_table_id
}

# Blackhole routes — spoke VPCs cannot talk to each other by default
# Add one blackhole per spoke CIDR
resource "aws_ec2_transit_gateway_route" "spoke_blackhole" {
  count                          = length(var.spoke_cidrs)
  destination_cidr_block         = var.spoke_cidrs[count.index]
  blackhole                      = true
  transit_gateway_route_table_id = var.spoke_route_table_id
}

###############################################################
# CORE route table routes
# Used by hub VPCs (inspect, endpoints, ingress)
###############################################################

# Return routes — core RT needs to know how to reach each spoke CIDR
# so that return traffic from NAT/inspect reaches the right spoke VPC
# These are added per spoke attachment (done in tgw_spoke_attachments via propagation)
# But for the ingress VPC specifically, add explicit routes:

# Ingress VPC CIDR → ingress attachment (return path for inbound traffic)
resource "aws_ec2_transit_gateway_route" "core_to_ingress" {
  destination_cidr_block         = var.ingress_vpc_cidr
  transit_gateway_attachment_id  = var.ingress_attachment_id
  transit_gateway_route_table_id = var.core_route_table_id
}

# Inspect VPC CIDR → inspect attachment
resource "aws_ec2_transit_gateway_route" "core_to_inspect" {
  destination_cidr_block         = var.inspect_vpc_cidr
  transit_gateway_attachment_id  = var.inspect_attachment_id
  transit_gateway_route_table_id = var.core_route_table_id
}

# Endpoints VPC CIDR → endpoints attachment
resource "aws_ec2_transit_gateway_route" "core_to_endpoints" {
  destination_cidr_block         = var.endpoints_vpc_cidr
  transit_gateway_attachment_id  = var.endpoints_attachment_id
  transit_gateway_route_table_id = var.core_route_table_id
}
