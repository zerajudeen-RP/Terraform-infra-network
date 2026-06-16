###############################################################
# Module: inspect_vpc
# Centralized Egress VPC — NFW + NAT
# VPC CIDR: var.vpc_cidr (default 10.220.200.0/22)
#
# All subnet CIDRs are calculated using cidrsubnet().
# Layout for a /22 (1024 IPs):
#   NFW subnets:  3× /24 (first 3 /24s) = 768 IPs
#   TGW subnets:  3× /28 from remaining space
#   NAT subnets:  3× /28 from remaining space
#
# Approach:
#   /24 subnets: cidrsubnet(vpc_cidr, 2, 0/1/2) → /24 slots 0-2
#   /28 subnets: cidrsubnet(vpc_cidr, 6, N) from slot 48+ (within last /24)
#
# Route table summary:
#   TGW-attach RT : 0.0.0.0/0 → NFW endpoint (egress to firewall)
#   Firewall RT   : 0.0.0.0/0 → NAT GW, RFC1918 → TGW
#   NAT RT        : 0.0.0.0/0 → IGW, RFC1918 → TGW
###############################################################

###############################################################
# VPC
###############################################################
resource "aws_vpc" "this" {
  ipv4_ipam_pool_id   = var.ipam_pool_id != "" ? var.ipam_pool_id : null
  ipv4_netmask_length = var.ipam_pool_id != "" ? var.ipam_netmask_length : null
  cidr_block          = var.ipam_pool_id == "" ? var.vpc_cidr : null

  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(var.tags, { Name = "${var.name}-${var.environment}-inspect-vpc" })
}

###############################################################
# Internet Gateway
###############################################################
resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = merge(var.tags, { Name = "${var.name}-${var.environment}-inspect-igw" })
}

###############################################################
# Subnet CIDR calculations
#
# VPC /22 layout:
#   Firewall: 3× /24 — cidrsubnet(vpc, 2, 0), (vpc, 2, 1), (vpc, 2, 2)
#   The last /24 (cidrsubnet(vpc, 2, 3)) is split into /28s:
#     TGW: slots 0, 1, 2
#     NAT: slots 3, 4, 5
###############################################################
locals {
  vpc_cidr    = aws_vpc.this.cidr_block
  last_slash24 = cidrsubnet(local.vpc_cidr, 2, 3)

  fw_subnet_cidrs = [
    cidrsubnet(local.vpc_cidr, 2, 0), # AZ-a /24
    cidrsubnet(local.vpc_cidr, 2, 1), # AZ-b /24
    cidrsubnet(local.vpc_cidr, 2, 2), # AZ-c /24
  ]
  # /28 from the last /24 (newbits=4 from /24 → /28)
  tgw_subnet_cidrs = [
    cidrsubnet(local.last_slash24, 4, 0), # AZ-a
    cidrsubnet(local.last_slash24, 4, 1), # AZ-b
    cidrsubnet(local.last_slash24, 4, 2), # AZ-c
  ]
  nat_subnet_cidrs = [
    cidrsubnet(local.last_slash24, 4, 3), # AZ-a
    cidrsubnet(local.last_slash24, 4, 4), # AZ-b
    cidrsubnet(local.last_slash24, 4, 5), # AZ-c
  ]
}

###############################################################
# Subnets
###############################################################
resource "aws_subnet" "tgw" {
  count             = length(var.azs)
  vpc_id            = aws_vpc.this.id
  cidr_block        = local.tgw_subnet_cidrs[count.index]
  availability_zone = var.azs[count.index]
  tags = merge(var.tags, { Name = "${var.name}-${var.environment}-inspect-tgw-${substr(var.azs[count.index], -1, 1)}", Tier = "tgw-attach" })
}

resource "aws_subnet" "firewall" {
  count             = length(var.azs)
  vpc_id            = aws_vpc.this.id
  cidr_block        = local.fw_subnet_cidrs[count.index]
  availability_zone = var.azs[count.index]
  tags = merge(var.tags, { Name = "${var.name}-${var.environment}-inspect-fw-${substr(var.azs[count.index], -1, 1)}", Tier = "firewall" })
}

resource "aws_subnet" "nat" {
  count             = length(var.azs)
  vpc_id            = aws_vpc.this.id
  cidr_block        = local.nat_subnet_cidrs[count.index]
  availability_zone = var.azs[count.index]
  tags = merge(var.tags, { Name = "${var.name}-${var.environment}-inspect-nat-${substr(var.azs[count.index], -1, 1)}", Tier = "nat" })
}

###############################################################
# EIPs + NAT Gateways
###############################################################
resource "aws_eip" "nat" {
  count  = length(var.azs)
  domain = "vpc"
  tags   = merge(var.tags, { Name = "${var.name}-${var.environment}-inspect-nat-eip-${substr(var.azs[count.index], -1, 1)}" })
}

resource "aws_nat_gateway" "this" {
  count         = length(var.azs)
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.nat[count.index].id
  tags          = merge(var.tags, { Name = "${var.name}-${var.environment}-inspect-natgw-${substr(var.azs[count.index], -1, 1)}" })
  depends_on    = [aws_internet_gateway.this]
}

###############################################################
# TGW Attachment subnet RT — 0.0.0.0/0 → NFW endpoint
###############################################################
resource "aws_route_table" "tgw" {
  count  = length(var.azs)
  vpc_id = aws_vpc.this.id
  tags   = merge(var.tags, { Name = "${var.name}-${var.environment}-inspect-rt-tgw-${substr(var.azs[count.index], -1, 1)}" })
}
resource "aws_route_table_association" "tgw" {
  count          = length(var.azs)
  subnet_id      = aws_subnet.tgw[count.index].id
  route_table_id = aws_route_table.tgw[count.index].id
}

###############################################################
# Firewall subnet RT — 0.0.0.0/0 → NAT, RFC1918 → TGW
###############################################################
resource "aws_route_table" "firewall" {
  count  = length(var.azs)
  vpc_id = aws_vpc.this.id
  tags   = merge(var.tags, { Name = "${var.name}-${var.environment}-inspect-rt-fw-${substr(var.azs[count.index], -1, 1)}" })
}
resource "aws_route_table_association" "firewall" {
  count          = length(var.azs)
  subnet_id      = aws_subnet.firewall[count.index].id
  route_table_id = aws_route_table.firewall[count.index].id
}
resource "aws_route" "fw_to_nat" {
  count                  = length(var.azs)
  route_table_id         = aws_route_table.firewall[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[count.index].id
}
resource "aws_route" "fw_to_tgw" {
  count                  = length(var.azs)
  route_table_id         = aws_route_table.firewall[count.index].id
  destination_cidr_block = "10.220.0.0/16"
  transit_gateway_id     = var.tgw_id
  depends_on             = [aws_ec2_transit_gateway_vpc_attachment.this]
}

###############################################################
# NAT subnet RT — 0.0.0.0/0 → IGW, RFC1918 → TGW
###############################################################
resource "aws_route_table" "nat" {
  count  = length(var.azs)
  vpc_id = aws_vpc.this.id
  tags   = merge(var.tags, { Name = "${var.name}-${var.environment}-inspect-rt-nat-${substr(var.azs[count.index], -1, 1)}" })
}
resource "aws_route_table_association" "nat" {
  count          = length(var.azs)
  subnet_id      = aws_subnet.nat[count.index].id
  route_table_id = aws_route_table.nat[count.index].id
}
resource "aws_route" "nat_to_igw" {
  count                  = length(var.azs)
  route_table_id         = aws_route_table.nat[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}
resource "aws_route" "nat_to_tgw" {
  count                  = length(var.azs)
  route_table_id         = aws_route_table.nat[count.index].id
  destination_cidr_block = "10.220.0.0/16"
  transit_gateway_id     = var.tgw_id
  depends_on             = [aws_ec2_transit_gateway_vpc_attachment.this]
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
  appliance_mode_support                          = "enable"
  tags = merge(var.tags, { Name = "${var.name}-${var.environment}-inspect-tgw-attach" })
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
