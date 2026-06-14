###############################################################
# Module: inspect_vpc
# Centralized Egress + GWLB hub VPC
# CIDR: 10.220.128.0/22
#
# Route table summary:
#   tgw-attach subnet RT  : 0.0.0.0/0 → GWLBe (send everything to firewall first)
#   firewall subnet RT    : 0.0.0.0/0 → NAT GW (post-inspection internet egress)
#                           10.220.0.0/16 → TGW (return RFC1918 to spokes)
#   nat subnet RT         : 0.0.0.0/0 → IGW (internet breakout)
#                           10.220.0.0/16 → TGW (return RFC1918 to spokes)
###############################################################

###############################################################
# VPC — IPAM-backed
# When ipam_pool_id is provided, AWS assigns the CIDR from the
# pool automatically (ipv4_ipam_pool_id + ipv4_netmask_length).
# vpc_cidr is still used for subnet CIDRs and route entries.
###############################################################
resource "aws_vpc" "this" {
  ipv4_ipam_pool_id   = var.ipam_pool_id != "" ? var.ipam_pool_id : null
  ipv4_netmask_length = var.ipam_pool_id != "" ? var.ipam_netmask_length : null
  cidr_block          = var.ipam_pool_id == "" ? var.vpc_cidr : null

  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(var.tags, {
    Name = "${var.name}-${var.environment}-inspect-vpc"
  })
}

###############################################################
# Internet Gateway
###############################################################
resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, {
    Name = "${var.name}-${var.environment}-inspect-igw"
  })
}

###############################################################
# Subnet CIDR calculations using cidrsubnet()
#
# The VPC CIDR is a /22 (e.g. 10.220.192.0/22 = 1024 IPs).
# We carve it into /28 slices (16 IPs each) for TGW, FW, NAT.
# Layout per AZ (offset by 64 per AZ to keep them grouped):
#
#   AZ-a: base+0  (TGW), base+16 (FW), base+32 (NAT)
#   AZ-b: base+64 (TGW), base+80 (FW), base+96 (NAT)
#   AZ-c: base+128(TGW), base+144(FW), base+160(NAT)
#
# cidrsubnet(vpc_cidr, newbits, netnum):
#   newbits = 28 - 22 = 6 extra bits
#   netnum  = sequential /28 index within the /22
###############################################################
locals {
  # Use the actual IPAM-assigned VPC CIDR (aws_vpc.this.cidr_block)
  # not var.vpc_cidr, so subnets are always carved from the real VPC CIDR.
  # newbits = 6 because /22 + 6 = /28
  vpc_cidr = aws_vpc.this.cidr_block

  tgw_subnet_cidrs = [
    cidrsubnet(local.vpc_cidr, 6, 0),  # AZ-a
    cidrsubnet(local.vpc_cidr, 6, 4),  # AZ-b
    cidrsubnet(local.vpc_cidr, 6, 8),  # AZ-c
  ]
  fw_subnet_cidrs = [
    cidrsubnet(local.vpc_cidr, 6, 1),  # AZ-a
    cidrsubnet(local.vpc_cidr, 6, 5),  # AZ-b
    cidrsubnet(local.vpc_cidr, 6, 9),  # AZ-c
  ]
  nat_subnet_cidrs = [
    cidrsubnet(local.vpc_cidr, 6, 2),  # AZ-a
    cidrsubnet(local.vpc_cidr, 6, 6),  # AZ-b
    cidrsubnet(local.vpc_cidr, 6, 10), # AZ-c
  ]
}

###############################################################
# Subnets — TGW Attachment (one per AZ)
###############################################################
resource "aws_subnet" "tgw" {
  count             = length(var.azs)
  vpc_id            = aws_vpc.this.id
  cidr_block        = local.tgw_subnet_cidrs[count.index]
  availability_zone = var.azs[count.index]

  tags = merge(var.tags, {
    Name = "${var.name}-${var.environment}-inspect-tgw-${substr(var.azs[count.index], -1, 1)}"
    Tier = "tgw-attach"
  })
}

###############################################################
# Subnets — Firewall / GWLB (one per AZ)
###############################################################
resource "aws_subnet" "firewall" {
  count             = length(var.azs)
  vpc_id            = aws_vpc.this.id
  cidr_block        = local.fw_subnet_cidrs[count.index]
  availability_zone = var.azs[count.index]

  tags = merge(var.tags, {
    Name = "${var.name}-${var.environment}-inspect-fw-${substr(var.azs[count.index], -1, 1)}"
    Tier = "firewall"
  })
}

###############################################################
# Subnets — NAT Gateway (one per AZ)
###############################################################
resource "aws_subnet" "nat" {
  count             = length(var.azs)
  vpc_id            = aws_vpc.this.id
  cidr_block        = local.nat_subnet_cidrs[count.index]
  availability_zone = var.azs[count.index]

  tags = merge(var.tags, {
    Name = "${var.name}-${var.environment}-inspect-nat-${substr(var.azs[count.index], -1, 1)}"
    Tier = "nat"
  })
}

###############################################################
# Elastic IPs + NAT Gateways (one per AZ)
###############################################################
resource "aws_eip" "nat" {
  count  = length(var.azs)
  domain = "vpc"

  tags = merge(var.tags, {
    Name = "${var.name}-${var.environment}-inspect-nat-eip-${substr(var.azs[count.index], -1, 1)}"
  })
}

resource "aws_nat_gateway" "this" {
  count         = length(var.azs)
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.nat[count.index].id

  tags = merge(var.tags, {
    Name = "${var.name}-${var.environment}-inspect-natgw-${substr(var.azs[count.index], -1, 1)}"
  })

  depends_on = [aws_internet_gateway.this]
}

###############################################################
# Gateway Load Balancer (GWLB)
###############################################################
resource "aws_lb" "gwlb" {
  name               = "${var.name}-${var.environment}-gwlb"
  load_balancer_type = "gateway"
  subnets            = aws_subnet.firewall[*].id

  tags = merge(var.tags, {
    Name = "${var.name}-${var.environment}-gwlb"
  })
}

resource "aws_lb_target_group" "gwlb" {
  name        = "${var.name}-${var.environment}-gwlb-tg"
  port        = 6081
  protocol    = "GENEVE"
  vpc_id      = aws_vpc.this.id
  target_type = "instance"

  health_check {
    protocol = "TCP"
    port     = 80
  }

  tags = merge(var.tags, {
    Name = "${var.name}-${var.environment}-gwlb-tg"
  })
}

resource "aws_lb_listener" "gwlb" {
  load_balancer_arn = aws_lb.gwlb.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.gwlb.arn
  }

  tags = merge(var.tags, {
    Name = "${var.name}-${var.environment}-gwlb-listener"
  })
}

###############################################################
# GWLB Endpoint Service
# Exposes the GWLB as a PrivateLink endpoint service
###############################################################
resource "aws_vpc_endpoint_service" "gwlb" {
  acceptance_required        = false
  gateway_load_balancer_arns = [aws_lb.gwlb.arn]

  tags = merge(var.tags, {
    Name = "${var.name}-${var.environment}-gwlb-endpoint-svc"
  })
}

###############################################################
# GWLB VPC Endpoints — one per AZ inside inspect VPC
# TGW attachment subnet RT points here so egress traffic
# hits the firewall appliance before NAT
###############################################################
resource "aws_vpc_endpoint" "gwlb" {
  count             = length(var.azs)
  vpc_id            = aws_vpc.this.id
  service_name      = aws_vpc_endpoint_service.gwlb.service_name
  vpc_endpoint_type = "GatewayLoadBalancer"
  subnet_ids        = [aws_subnet.firewall[count.index].id]

  tags = merge(var.tags, {
    Name = "${var.name}-${var.environment}-inspect-gwlbe-${substr(var.azs[count.index], -1, 1)}"
  })
}

###############################################################
# S3 + DynamoDB Gateway Endpoints
###############################################################
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids = concat(
    aws_route_table.tgw[*].id,
    aws_route_table.firewall[*].id,
    aws_route_table.nat[*].id
  )

  tags = merge(var.tags, {
    Name = "${var.name}-${var.environment}-inspect-s3-endpoint"
  })
}

resource "aws_vpc_endpoint" "dynamodb" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.dynamodb"
  vpc_endpoint_type = "Gateway"
  route_table_ids = concat(
    aws_route_table.tgw[*].id,
    aws_route_table.firewall[*].id,
    aws_route_table.nat[*].id
  )

  tags = merge(var.tags, {
    Name = "${var.name}-${var.environment}-inspect-dynamodb-endpoint"
  })
}

###############################################################
# Route Tables — TGW Attachment Subnets
#
# Traffic arriving from TGW (spoke egress) is sent straight
# to the GWLBe so the firewall appliance inspects it before
# it reaches the NAT gateway.
# S3/DynamoDB gateway endpoints added so inspect VPC itself
# can reach those services locally.
###############################################################
resource "aws_route_table" "tgw" {
  count  = length(var.azs)
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, {
    Name = "${var.name}-${var.environment}-inspect-rt-tgw-${substr(var.azs[count.index], -1, 1)}"
  })
}

resource "aws_route_table_association" "tgw" {
  count          = length(var.azs)
  subnet_id      = aws_subnet.tgw[count.index].id
  route_table_id = aws_route_table.tgw[count.index].id
}

# 0.0.0.0/0 → GWLBe
# Note: when AWS Network Firewall is used, the root module overrides
# these routes by adding explicit NFW endpoint routes via
# aws_route resources in main.tf after the NFW module runs.
resource "aws_route" "tgw_to_gwlb" {
  count                  = length(var.azs)
  route_table_id         = aws_route_table.tgw[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  vpc_endpoint_id        = aws_vpc_endpoint.gwlb[count.index].id
}

###############################################################
# Route Tables — Firewall Subnets
#
# Post-inspection traffic:
#   - Internet-bound (0.0.0.0/0) → NAT Gateway (same AZ)
#   - RFC1918 return traffic (10.220.0.0/16) → TGW
# S3/DynamoDB hit gateway endpoints directly.
###############################################################
resource "aws_route_table" "firewall" {
  count  = length(var.azs)
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, {
    Name = "${var.name}-${var.environment}-inspect-rt-fw-${substr(var.azs[count.index], -1, 1)}"
  })
}

resource "aws_route_table_association" "firewall" {
  count          = length(var.azs)
  subnet_id      = aws_subnet.firewall[count.index].id
  route_table_id = aws_route_table.firewall[count.index].id
}

# 0.0.0.0/0 → NAT GW (internet egress, AZ-local)
resource "aws_route" "fw_to_nat" {
  count                  = length(var.azs)
  route_table_id         = aws_route_table.firewall[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[count.index].id
}

# 10.220.0.0/16 → TGW (return path for all MCT AU RFC1918 traffic)
resource "aws_route" "fw_to_tgw" {
  count                  = length(var.azs)
  route_table_id         = aws_route_table.firewall[count.index].id
  destination_cidr_block = "10.220.0.0/16"
  transit_gateway_id     = var.tgw_id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.this]
}

###############################################################
# Route Tables — NAT Gateway Subnets
#
# Internet response traffic returns here via IGW.
# RFC1918 destined traffic (return to spokes) goes back via TGW.
# S3/DynamoDB hit gateway endpoints directly.
###############################################################
resource "aws_route_table" "nat" {
  count  = length(var.azs)
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, {
    Name = "${var.name}-${var.environment}-inspect-rt-nat-${substr(var.azs[count.index], -1, 1)}"
  })
}

resource "aws_route_table_association" "nat" {
  count          = length(var.azs)
  subnet_id      = aws_subnet.nat[count.index].id
  route_table_id = aws_route_table.nat[count.index].id
}

# 0.0.0.0/0 → IGW (internet breakout)
resource "aws_route" "nat_to_igw" {
  count                  = length(var.azs)
  route_table_id         = aws_route_table.nat[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

# 10.220.0.0/16 → TGW (return RFC1918 responses back to spokes)
resource "aws_route" "nat_to_tgw" {
  count                  = length(var.azs)
  route_table_id         = aws_route_table.nat[count.index].id
  destination_cidr_block = "10.220.0.0/16"
  transit_gateway_id     = var.tgw_id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.this]
}

###############################################################
# TGW Attachment
###############################################################
resource "aws_ec2_transit_gateway_vpc_attachment" "this" {
  transit_gateway_id                              = var.tgw_id
  vpc_id                                          = aws_vpc.this.id
  subnet_ids                                      = aws_subnet.tgw[*].id
  transit_gateway_default_route_table_association = false
  transit_gateway_default_route_table_propagation = false
  appliance_mode_support                          = "enable" # Required for stateful inspection

  tags = merge(var.tags, {
    Name = "${var.name}-${var.environment}-inspect-tgw-attach"
  })
}

resource "aws_ec2_transit_gateway_route_table_association" "this" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.this.id
  transit_gateway_route_table_id = var.tgw_core_rt_id
}

resource "aws_ec2_transit_gateway_route_table_propagation" "core" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.this.id
  transit_gateway_route_table_id = var.tgw_core_rt_id
}

###############################################################
# Data sources
###############################################################
data "aws_region" "current" {}
