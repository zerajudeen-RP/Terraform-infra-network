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
#   2. aws_ec2_transit_gateway_route_table_propagation  — propagates
#      the workload VPC CIDR into the spoke route table so the hub
#      knows how to return traffic to the workload VPC
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

resource "aws_ec2_transit_gateway_route_table_propagation" "spoke" {
  for_each = var.spoke_attachment_ids

  transit_gateway_attachment_id  = each.value
  transit_gateway_route_table_id = var.tgw_spoke_rt_id
}
