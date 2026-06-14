###############################################################
# Module: tgw_spoke_attachments
# Associates and propagates cross-account TGW attachments
#
# When a workload account creates a TGW attachment, it cannot
# associate or propagate routes into the hub's route tables
# because those route tables belong to the hub account.
# This module runs in the HUB account and performs:
#   1. aws_ec2_transit_gateway_route_table_association  — attaches
#      the workload VPC attachment to the spoke route table
#   2. aws_ec2_transit_gateway_route_table_propagation (spoke RT) —
#      propagates the workload VPC CIDR into the spoke route table
#   3. aws_ec2_transit_gateway_route_table_propagation (core RT) —
#      propagates the workload VPC CIDR into the CORE route table
#      so that return traffic from NAT/inspect can find the spoke VPC.
#      Without this, packets from the internet destined for the workload
#      EC2 arrive at the inspect VPC NAT GW, get sent back through TGW,
#      but the core RT has no route to the workload CIDR → dropped.
#
# Usage: add one entry to var.spoke_attachment_ids per workload
# account/VPC after the workload account has applied and the
# attachment ID is visible in the TGW console.
###############################################################

resource "aws_ec2_transit_gateway_route_table_association" "spoke" {
  for_each = var.spoke_attachment_ids

  transit_gateway_attachment_id  = each.value
  transit_gateway_route_table_id = var.tgw_spoke_rt_id
}

# Propagate spoke CIDR into spoke RT
# (allows spoke VPCs to know about each other's CIDRs — blocked by blackhole routes in tgw_routes)
resource "aws_ec2_transit_gateway_route_table_propagation" "spoke" {
  for_each = var.spoke_attachment_ids

  transit_gateway_attachment_id  = each.value
  transit_gateway_route_table_id = var.tgw_spoke_rt_id
}

# Propagate spoke CIDR into core RT
# CRITICAL for egress return path:
#   Internet → IGW → NAT GW → firewall subnet → TGW (fw_to_tgw / nat_to_tgw routes)
#   TGW looks up core RT for destination (workload EC2 IP) → must find spoke CIDR here
#   → forwards to spoke TGW attachment → workload VPC → EC2
resource "aws_ec2_transit_gateway_route_table_propagation" "spoke_to_core" {
  for_each = var.spoke_attachment_ids

  transit_gateway_attachment_id  = each.value
  transit_gateway_route_table_id = var.tgw_core_rt_id
}
