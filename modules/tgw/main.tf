###############################################################
# Module: tgw
# Creates Transit Gateway + two route tables (core + spoke)
###############################################################

resource "aws_ec2_transit_gateway" "this" {
  description                     = "${var.name}-${var.environment} Transit Gateway"
  amazon_side_asn                 = var.asn
  dns_support                     = "enable"
  vpn_ecmp_support                = "enable"
  default_route_table_association = "disable"
  default_route_table_propagation = "disable"
  auto_accept_shared_attachments  = "enable"

  tags = merge(var.tags, {
    Name = "${var.name}-${var.environment}-tgw"
  })
}

###############################################################
# Route Tables
###############################################################

resource "aws_ec2_transit_gateway_route_table" "core" {
  transit_gateway_id = aws_ec2_transit_gateway.this.id

  tags = merge(var.tags, {
    Name = "${var.name}-${var.environment}-tgw-rt-core"
  })
}

resource "aws_ec2_transit_gateway_route_table" "spoke" {
  transit_gateway_id = aws_ec2_transit_gateway.this.id

  tags = merge(var.tags, {
    Name = "${var.name}-${var.environment}-tgw-rt-spoke"
  })
}
