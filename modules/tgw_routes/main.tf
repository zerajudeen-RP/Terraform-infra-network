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

# Ingress VPC CIDR → ingress attachment
# Spoke VPCs must reach the ingress VPC directly (ALB health checks + response traffic).
# Without this, return traffic from the workload EC2 to the ALB hits the default
# 0.0.0.0/0 → inspect route and gets sent to the inspect VPC instead of ingress.
resource "aws_ec2_transit_gateway_route" "spoke_to_ingress" {
  destination_cidr_block         = var.ingress_vpc_cidr
  transit_gateway_attachment_id  = var.ingress_attachment_id
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

###############################################################
# RFC 1918 Blackhole routes
#
# Deterministically drop traffic to unallocated private address
# space in both route tables. Prevents non-deterministic routing
# if Direct Connect or future VPCs are added covering overlapping
# RFC1918 ranges.
#
# Allocated ranges excluded (covered by explicit routes above):
#   10.220.128.0/17  — hub + workload VPC pool
#   10.220.192.0/19  — IPAM hub pool
#
# Everything else in RFC1918 is blackholed:
#   10.0.0.0/8 → blackhole (except 10.220.0.0/14 supernet carved out below)
#   172.16.0.0/12 → blackhole
#   192.168.0.0/16 → blackhole
###############################################################

# Core RT — blackhole unallocated 10.x space
# Use the largest non-overlapping blocks outside 10.220.0.0/14
resource "aws_ec2_transit_gateway_route" "core_blackhole_10_0" {
  destination_cidr_block         = "10.0.0.0/9"
  blackhole                      = true
  transit_gateway_route_table_id = var.core_route_table_id
}

resource "aws_ec2_transit_gateway_route" "core_blackhole_10_128" {
  destination_cidr_block         = "10.128.0.0/9"
  blackhole                      = true
  transit_gateway_route_table_id = var.core_route_table_id
}

resource "aws_ec2_transit_gateway_route" "core_blackhole_172" {
  destination_cidr_block         = "172.16.0.0/12"
  blackhole                      = true
  transit_gateway_route_table_id = var.core_route_table_id
}

resource "aws_ec2_transit_gateway_route" "core_blackhole_192" {
  destination_cidr_block         = "192.168.0.0/16"
  blackhole                      = true
  transit_gateway_route_table_id = var.core_route_table_id
}

# Spoke RT — same blackholes
resource "aws_ec2_transit_gateway_route" "spoke_blackhole_10_0" {
  destination_cidr_block         = "10.0.0.0/9"
  blackhole                      = true
  transit_gateway_route_table_id = var.spoke_route_table_id
}

resource "aws_ec2_transit_gateway_route" "spoke_blackhole_10_128" {
  destination_cidr_block         = "10.128.0.0/9"
  blackhole                      = true
  transit_gateway_route_table_id = var.spoke_route_table_id
}

resource "aws_ec2_transit_gateway_route" "spoke_blackhole_172" {
  destination_cidr_block         = "172.16.0.0/12"
  blackhole                      = true
  transit_gateway_route_table_id = var.spoke_route_table_id
}

resource "aws_ec2_transit_gateway_route" "spoke_blackhole_192" {
  destination_cidr_block         = "192.168.0.0/16"
  blackhole                      = true
  transit_gateway_route_table_id = var.spoke_route_table_id
}
