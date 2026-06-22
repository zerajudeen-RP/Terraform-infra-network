###############################################################
# Module: tgw_routes
# Populates TGW route table entries after all attachments exist.
# Spoke routes are created in BOTH spoke_stage and spoke_prod RTs
# with identical routes — isolation is via TGW attachment association,
# not route content.
#
# Cross-account routes: specific CIDRs can be excluded from
# blackholes and replaced with active routes to allow controlled
# spoke-to-spoke communication (e.g., vendor → shared-services).
###############################################################

locals {
  spoke_rt_ids = var.spoke_route_table_ids

  # Build a set of "rt_id-cidr" keys that should NOT be blackholed
  # because they have a cross-account active route instead
  cross_account_keys = toset([
    for r in var.cross_account_routes : "${r.spoke_rt_id}-${r.cidr}"
  ])

  # Flatten spoke RT × spoke CIDR for blackhole routes,
  # EXCLUDING any that have a cross-account route defined
  spoke_blackholes = flatten([
    for rt_idx, rt_id in local.spoke_rt_ids : [
      for cidr in var.spoke_cidrs : {
        key   = "${rt_idx}-${cidr}"
        rt_id = rt_id
        cidr  = cidr
      }
      if !contains(local.cross_account_keys, "${rt_id}-${cidr}")
    ]
  ])
}

###############################################################
# SPOKE route table routes (applied to EACH spoke RT)
###############################################################

# Default route → inspect VPC (egress via NFW + NAT)
resource "aws_ec2_transit_gateway_route" "spoke_default_to_inspect" {
  count                          = length(local.spoke_rt_ids)
  destination_cidr_block         = "0.0.0.0/0"
  transit_gateway_attachment_id  = var.inspect_attachment_id
  transit_gateway_route_table_id = local.spoke_rt_ids[count.index]
}

# Ingress VPC CIDR → ingress attachment (ALB health checks + return traffic)
resource "aws_ec2_transit_gateway_route" "spoke_to_ingress" {
  count                          = length(local.spoke_rt_ids)
  destination_cidr_block         = var.ingress_vpc_cidr
  transit_gateway_attachment_id  = var.ingress_attachment_id
  transit_gateway_route_table_id = local.spoke_rt_ids[count.index]
}

# Endpoints VPC CIDR → endpoints attachment (AWS service traffic)
resource "aws_ec2_transit_gateway_route" "spoke_to_endpoints" {
  count                          = length(local.spoke_rt_ids)
  destination_cidr_block         = var.endpoints_vpc_cidr
  transit_gateway_attachment_id  = var.endpoints_attachment_id
  transit_gateway_route_table_id = local.spoke_rt_ids[count.index]
}

# Blackhole — spoke VPCs cannot talk to each other
resource "aws_ec2_transit_gateway_route" "spoke_blackhole" {
  for_each                       = { for bh in local.spoke_blackholes : bh.key => bh }
  destination_cidr_block         = each.value.cidr
  blackhole                      = true
  transit_gateway_route_table_id = each.value.rt_id
}

# Cross-account active routes — replace blackholes for specific
# spoke-to-spoke communication (e.g., vendor → shared-services)
resource "aws_ec2_transit_gateway_route" "cross_account" {
  for_each = {
    for r in var.cross_account_routes : "${r.spoke_rt_id}-${r.cidr}" => r
  }

  destination_cidr_block         = each.value.cidr
  transit_gateway_attachment_id  = each.value.attachment_id
  transit_gateway_route_table_id = each.value.spoke_rt_id
}

# RFC1918 blackholes in spoke RTs
resource "aws_ec2_transit_gateway_route" "spoke_blackhole_10_0" {
  count                          = length(local.spoke_rt_ids)
  destination_cidr_block         = "10.0.0.0/9"
  blackhole                      = true
  transit_gateway_route_table_id = local.spoke_rt_ids[count.index]
}

resource "aws_ec2_transit_gateway_route" "spoke_blackhole_10_128" {
  count                          = length(local.spoke_rt_ids)
  destination_cidr_block         = "10.128.0.0/9"
  blackhole                      = true
  transit_gateway_route_table_id = local.spoke_rt_ids[count.index]
}

resource "aws_ec2_transit_gateway_route" "spoke_blackhole_172" {
  count                          = length(local.spoke_rt_ids)
  destination_cidr_block         = "172.16.0.0/12"
  blackhole                      = true
  transit_gateway_route_table_id = local.spoke_rt_ids[count.index]
}

resource "aws_ec2_transit_gateway_route" "spoke_blackhole_192" {
  count                          = length(local.spoke_rt_ids)
  destination_cidr_block         = "192.168.0.0/16"
  blackhole                      = true
  transit_gateway_route_table_id = local.spoke_rt_ids[count.index]
}

###############################################################
# CORE route table routes
###############################################################

resource "aws_ec2_transit_gateway_route" "core_to_ingress" {
  destination_cidr_block         = var.ingress_vpc_cidr
  transit_gateway_attachment_id  = var.ingress_attachment_id
  transit_gateway_route_table_id = var.core_route_table_id
}

resource "aws_ec2_transit_gateway_route" "core_to_inspect" {
  destination_cidr_block         = var.inspect_vpc_cidr
  transit_gateway_attachment_id  = var.inspect_attachment_id
  transit_gateway_route_table_id = var.core_route_table_id
}

resource "aws_ec2_transit_gateway_route" "core_to_endpoints" {
  destination_cidr_block         = var.endpoints_vpc_cidr
  transit_gateway_attachment_id  = var.endpoints_attachment_id
  transit_gateway_route_table_id = var.core_route_table_id
}

# RFC1918 blackholes in core RT
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
