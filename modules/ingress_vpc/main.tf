###############################################################
# Module: ingress_vpc
# Centralized Ingress VPC — IGW + NLB + ALB + TGW
# CIDR: allocated from IPAM
#
# Route table summary:
#   NLB subnet RT  : 0.0.0.0/0 → IGW  (internet-facing, direct)
#   ALB subnet RT  : <spoke-cidr> → TGW (forward to workload)
#   TGW attach RT  : local only
#
# GWLBe inspection on ingress is removed — AWS Network Firewall
# in the inspect VPC handles all inspection via the egress path.
# Adding a GWLB bump-in-the-wire on inbound requires a running
# firewall appliance registered in the GWLB target group; without
# targets the GWLB drops all traffic and the NLB is unreachable.
###############################################################

###############################################################
# VPC — IPAM-backed
###############################################################
resource "aws_vpc" "this" {
  ipv4_ipam_pool_id   = var.ipam_pool_id != "" ? var.ipam_pool_id : null
  ipv4_netmask_length = var.ipam_pool_id != "" ? var.ipam_netmask_length : null
  cidr_block          = var.ipam_pool_id == "" ? var.vpc_cidr : null

  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(var.tags, {
    Name = "${var.name}-${var.environment}-ingress-vpc"
  })
}

###############################################################
# Internet Gateway
###############################################################
resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, {
    Name = "${var.name}-${var.environment}-ingress-igw"
  })
}

###############################################################
# Subnet CIDR calculations using cidrsubnet()
#
# VPC is a /23 (512 IPs). Layout:
#   newbits = 5 gives /28 (23+5=28), newbits = 2 gives /25 (not needed here)
#   For NLB we need /27 so newbits = 4 (23+4=27)
#   For ALB/GWLBe/TGW we use /28 so newbits = 5 (23+5=28)
#
# The /23 has 32 x /28 slots. We group by AZ:
#   AZ-a: slots 0-7   (first 128 IPs)
#   AZ-b: slots 8-15  (next 128 IPs)
#   AZ-c: slots 16-23 (next 128 IPs)
#
# Per AZ layout:
#   slot+0 (/27)  → NLB     (slots 0,1 consumed — /27 = 2x /28)
#   slot+2 (/28)  → ALB
#   slot+3 (/28)  → GWLBe
#   slot+4 (/28)  → TGW
###############################################################
locals {
  vpc_cidr = aws_vpc.this.cidr_block

  # /27 subnets for NLB (newbits=4 because /23+4=/27)
  nlb_subnet_cidrs = [
    cidrsubnet(local.vpc_cidr, 4, 0),  # AZ-a
    cidrsubnet(local.vpc_cidr, 4, 4),  # AZ-b
    cidrsubnet(local.vpc_cidr, 4, 8),  # AZ-c
  ]
  # /28 subnets (newbits=5 because /23+5=/28)
  alb_subnet_cidrs = [
    cidrsubnet(local.vpc_cidr, 5, 4),  # AZ-a
    cidrsubnet(local.vpc_cidr, 5, 12), # AZ-b
    cidrsubnet(local.vpc_cidr, 5, 20), # AZ-c
  ]
  tgw_subnet_cidrs = [
    cidrsubnet(local.vpc_cidr, 5, 6),  # AZ-a
    cidrsubnet(local.vpc_cidr, 5, 14), # AZ-b
    cidrsubnet(local.vpc_cidr, 5, 22), # AZ-c
  ]
}

###############################################################
# Subnets — NLB (/27 per AZ — larger for NLB node IPs)
###############################################################
resource "aws_subnet" "nlb" {
  count                   = length(var.azs)
  vpc_id                  = aws_vpc.this.id
  cidr_block              = local.nlb_subnet_cidrs[count.index]
  availability_zone       = var.azs[count.index]
  map_public_ip_on_launch = false

  tags = merge(var.tags, {
    Name = "${var.name}-${var.environment}-ingress-nlb-${substr(var.azs[count.index], -1, 1)}"
    Tier = "nlb"
  })
}

###############################################################
# Subnets — ALB (/28 per AZ)
###############################################################
resource "aws_subnet" "alb" {
  count             = length(var.azs)
  vpc_id            = aws_vpc.this.id
  cidr_block        = local.alb_subnet_cidrs[count.index]
  availability_zone = var.azs[count.index]

  tags = merge(var.tags, {
    Name = "${var.name}-${var.environment}-ingress-alb-${substr(var.azs[count.index], -1, 1)}"
    Tier = "alb"
  })
}

###############################################################
# Subnets — TGW Attachment (/28 per AZ)
###############################################################
resource "aws_subnet" "tgw" {
  count             = length(var.azs)
  vpc_id            = aws_vpc.this.id
  cidr_block        = local.tgw_subnet_cidrs[count.index]
  availability_zone = var.azs[count.index]

  tags = merge(var.tags, {
    Name = "${var.name}-${var.environment}-ingress-tgw-${substr(var.azs[count.index], -1, 1)}"
    Tier = "tgw-attach"
  })
}

###############################################################
# Route Tables — NLB Subnets
# Direct internet access — 0.0.0.0/0 → IGW
###############################################################
resource "aws_route_table" "nlb" {
  count  = length(var.azs)
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, {
    Name = "${var.name}-${var.environment}-ingress-rt-nlb-${substr(var.azs[count.index], -1, 1)}"
  })
}

resource "aws_route_table_association" "nlb" {
  count          = length(var.azs)
  subnet_id      = aws_subnet.nlb[count.index].id
  route_table_id = aws_route_table.nlb[count.index].id
}

resource "aws_route" "nlb_to_igw" {
  count                  = length(var.azs)
  route_table_id         = aws_route_table.nlb[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

###############################################################
# Route Tables — ALB Subnets
#
# ALB sits internal to the VPC. After processing the request,
# it forwards traffic to spoke VPCs via TGW.
# Specific spoke CIDRs → TGW (not a default route, more precise).
# 0.0.0.0/0 → IGW is NOT added here — ALB is internal only.
###############################################################
resource "aws_route_table" "alb" {
  count  = length(var.azs)
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, {
    Name = "${var.name}-${var.environment}-ingress-rt-alb-${substr(var.azs[count.index], -1, 1)}"
  })
}

resource "aws_route_table_association" "alb" {
  count          = length(var.azs)
  subnet_id      = aws_subnet.alb[count.index].id
  route_table_id = aws_route_table.alb[count.index].id
}

# Spoke CIDRs → TGW (one route per spoke CIDR)
# Traffic from ALB to workload VPCs goes via TGW
resource "aws_route" "alb_to_tgw_spokes" {
  count                  = length(var.spoke_cidrs)
  route_table_id         = aws_route_table.alb[0].id
  destination_cidr_block = var.spoke_cidrs[count.index]
  transit_gateway_id     = var.tgw_id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.this]
}

resource "aws_route" "alb_to_tgw_spokes_b" {
  count                  = length(var.spoke_cidrs)
  route_table_id         = aws_route_table.alb[1].id
  destination_cidr_block = var.spoke_cidrs[count.index]
  transit_gateway_id     = var.tgw_id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.this]
}

resource "aws_route" "alb_to_tgw_spokes_c" {
  count                  = length(var.spoke_cidrs)
  route_table_id         = aws_route_table.alb[2].id
  destination_cidr_block = var.spoke_cidrs[count.index]
  transit_gateway_id     = var.tgw_id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.this]
}

###############################################################
# Route Tables — TGW Attachment Subnets
#
# These subnets are only used for TGW ENIs.
# No custom routes needed — local routing only.
# Return traffic from spoke VPCs arrives here via TGW and
# is forwarded to the ALB by the VPC local route table.
###############################################################
resource "aws_route_table" "tgw" {
  count  = length(var.azs)
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, {
    Name = "${var.name}-${var.environment}-ingress-rt-tgw-${substr(var.azs[count.index], -1, 1)}"
  })
}

resource "aws_route_table_association" "tgw" {
  count          = length(var.azs)
  subnet_id      = aws_subnet.tgw[count.index].id
  route_table_id = aws_route_table.tgw[count.index].id
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

  tags = merge(var.tags, {
    Name = "${var.name}-${var.environment}-ingress-tgw-attach"
  })
}

resource "aws_ec2_transit_gateway_route_table_association" "this" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.this.id
  transit_gateway_route_table_id = var.tgw_core_rt_id
}

###############################################################
# Security Groups
###############################################################

# NLB SG — internet-facing, allows 443 + 80
resource "aws_security_group" "nlb" {
  name        = "${var.name}-${var.environment}-ingress-nlb-sg"
  description = "NLB - allow inbound HTTPS/HTTP from internet"
  vpc_id      = aws_vpc.this.id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS from internet"
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTP from internet (redirect to HTTPS)"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.name}-${var.environment}-ingress-nlb-sg"
  })
}

# ALB SG — internal, only accepts traffic from NLB
resource "aws_security_group" "alb" {
  name        = "${var.name}-${var.environment}-ingress-alb-sg"
  description = "ALB - allow inbound only from NLB security group"
  vpc_id      = aws_vpc.this.id

  ingress {
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.nlb.id]
    description     = "HTTPS from NLB only"
  }

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.nlb.id]
    description     = "HTTP from NLB only"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.name}-${var.environment}-ingress-alb-sg"
  })
}
