###############################################################
# Module: ingress_vpc
# Centralized Ingress VPC — IGW + NFW + NLB + ALB + TGW
# CIDR: allocated from IPAM (/23)
#
# Confirmed inbound traffic flow (architect-approved):
#   Internet → IGW → IGW Edge Association RT
#   → NFW VPC Endpoint (firewall subnets, per AZ)
#   → NLB subnet → NLB
#   → ALB subnet → ALB (+WAF)
#   → TGW → Workload EC2
#
# Route table summary:
#   IGW edge RT    : <nlb-cidr>/27 → NFW endpoint (per AZ)
#                    <alb-cidr>/28 → NFW endpoint (per AZ)
#   Firewall RT    : 0.0.0.0/0 → IGW
#                    <vpc-cidr> → local
#   NLB subnet RT  : 0.0.0.0/0 → NFW endpoint (return path inspected)
#   ALB subnet RT  : <spoke-cidr> → TGW
#                    0.0.0.0/0 → NFW endpoint (return path inspected)
#   TGW attach RT  : <nlb-cidr> → NFW endpoint
#                    <alb-cidr> → NFW endpoint
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
# Subnet CIDR calculations
#
# VPC is a /23 (512 IPs). newbits from /23:
#   +4 = /27 (32 IPs) for NLB and ALB (architect requires /27 min for ALB scaling)
#   +5 = /28 (16 IPs) for firewall and TGW
#
# Per-AZ slot layout (/27 units, newbits=4):
#   AZ-a: slot 0 (/27 NLB), slot 1 (/27 ALB), /28 slots 4+5 (FW+TGW)
#   AZ-b: slot 4 (/27 NLB), slot 5 (/27 ALB), /28 slots 12+13 (FW+TGW)
#   AZ-c: slot 8 (/27 NLB), slot 9 (/27 ALB), /28 slots 20+21 (FW+TGW)
###############################################################
locals {
  vpc_cidr = aws_vpc.this.cidr_block

  # /27 — NLB (newbits=4)
  nlb_subnet_cidrs = [
    cidrsubnet(local.vpc_cidr, 4, 0),  # AZ-a
    cidrsubnet(local.vpc_cidr, 4, 4),  # AZ-b
    cidrsubnet(local.vpc_cidr, 4, 8),  # AZ-c
  ]
  # /27 — ALB (newbits=4) — architect requires /27 minimum for ALB scaling headroom
  alb_subnet_cidrs = [
    cidrsubnet(local.vpc_cidr, 4, 1),  # AZ-a
    cidrsubnet(local.vpc_cidr, 4, 5),  # AZ-b
    cidrsubnet(local.vpc_cidr, 4, 9),  # AZ-c
  ]
  # /28 — Firewall / NFW endpoints (newbits=5)
  firewall_subnet_cidrs = [
    cidrsubnet(local.vpc_cidr, 5, 4),  # AZ-a
    cidrsubnet(local.vpc_cidr, 5, 12), # AZ-b
    cidrsubnet(local.vpc_cidr, 5, 20), # AZ-c
  ]
  # /28 — TGW (newbits=5)
  tgw_subnet_cidrs = [
    cidrsubnet(local.vpc_cidr, 5, 5),  # AZ-a
    cidrsubnet(local.vpc_cidr, 5, 13), # AZ-b
    cidrsubnet(local.vpc_cidr, 5, 21), # AZ-c
  ]
}

###############################################################
# Subnets — NLB (/27 per AZ)
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
# Subnets — Firewall / NFW endpoints (/28 per AZ)
###############################################################
resource "aws_subnet" "firewall" {
  count             = length(var.azs)
  vpc_id            = aws_vpc.this.id
  cidr_block        = local.firewall_subnet_cidrs[count.index]
  availability_zone = var.azs[count.index]

  tags = merge(var.tags, {
    Name = "${var.name}-${var.environment}-ingress-fw-${substr(var.azs[count.index], -1, 1)}"
    Tier = "firewall"
  })
}

###############################################################
# Subnets — ALB (/27 per AZ — sized for ALB scaling headroom)
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
# IGW Edge Association Route Table
#
# Attached to the IGW itself (gateway route table).
# Intercepts inbound packets before they reach the NLB/ALB.
# Each NLB and ALB subnet CIDR is redirected to the AZ-local
# NFW endpoint for inspection first.
#
# NFW endpoint IDs are injected after NFW is deployed via
# var.nfw_endpoint_ids (passed from root module).
###############################################################
resource "aws_route_table" "igw_edge" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, {
    Name = "${var.name}-${var.environment}-ingress-rt-igw-edge"
  })
}

# Attach to IGW (gateway route table association)
resource "aws_route_table_association" "igw_edge" {
  gateway_id     = aws_internet_gateway.this.id
  route_table_id = aws_route_table.igw_edge.id
}

# NLB subnet CIDRs → NFW endpoint (per AZ)
resource "aws_route" "igw_to_nfw_for_nlb" {
  count                  = length(var.azs)
  route_table_id         = aws_route_table.igw_edge.id
  destination_cidr_block = local.nlb_subnet_cidrs[count.index]
  vpc_endpoint_id        = var.nfw_endpoint_ids[count.index]
}

# ALB subnet CIDRs → NFW endpoint (per AZ)
resource "aws_route" "igw_to_nfw_for_alb" {
  count                  = length(var.azs)
  route_table_id         = aws_route_table.igw_edge.id
  destination_cidr_block = local.alb_subnet_cidrs[count.index]
  vpc_endpoint_id        = var.nfw_endpoint_ids[count.index]
}

###############################################################
# Route Tables — Firewall Subnets
#
# After NFW inspects and approves the packet it returns it
# to the firewall subnet. From here:
#   - Internet-bound responses go back to IGW (0.0.0.0/0 → IGW)
#   - Local VPC traffic stays local
###############################################################
resource "aws_route_table" "firewall" {
  count  = length(var.azs)
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, {
    Name = "${var.name}-${var.environment}-ingress-rt-fw-${substr(var.azs[count.index], -1, 1)}"
  })
}

resource "aws_route_table_association" "firewall" {
  count          = length(var.azs)
  subnet_id      = aws_subnet.firewall[count.index].id
  route_table_id = aws_route_table.firewall[count.index].id
}

# 0.0.0.0/0 → IGW (post-inspection traffic returns toward IGW → NLB)
resource "aws_route" "firewall_to_igw" {
  count                  = length(var.azs)
  route_table_id         = aws_route_table.firewall[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

###############################################################
# Route Tables — NLB Subnets
#
# Inbound: traffic arrives from NFW (via firewall subnet) — local routing.
# Return/response: NLB response packets must go back through NFW
#   so the firewall sees both directions (stateful inspection).
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

# 0.0.0.0/0 → NFW endpoint (return traffic also inspected)
resource "aws_route" "nlb_to_nfw" {
  count                  = length(var.azs)
  route_table_id         = aws_route_table.nlb[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  vpc_endpoint_id        = var.nfw_endpoint_ids[count.index]
}

###############################################################
# Route Tables — ALB Subnets
#
# Spoke CIDRs → TGW (forward to workload VPCs).
# Return traffic (responses from ALB to internet) → NFW endpoint.
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

# Spoke CIDRs → TGW
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

# 0.0.0.0/0 → NFW endpoint (ALB response traffic inspected)
resource "aws_route" "alb_to_nfw" {
  count                  = length(var.azs)
  route_table_id         = aws_route_table.alb[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  vpc_endpoint_id        = var.nfw_endpoint_ids[count.index]
}

###############################################################
# Route Tables — TGW Attachment Subnets
#
# Traffic arriving from TGW (workload → ALB/NLB) must be
# inspected by NFW before reaching the ALB/NLB.
# Route NLB and ALB subnet CIDRs → NFW endpoint per AZ.
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

# NLB subnet CIDRs → NFW endpoint
resource "aws_route" "tgw_to_nfw_for_nlb" {
  count                  = length(var.azs)
  route_table_id         = aws_route_table.tgw[count.index].id
  destination_cidr_block = local.nlb_subnet_cidrs[count.index]
  vpc_endpoint_id        = var.nfw_endpoint_ids[count.index]
}

# ALB subnet CIDRs → NFW endpoint
resource "aws_route" "tgw_to_nfw_for_alb" {
  count                  = length(var.azs)
  route_table_id         = aws_route_table.tgw[count.index].id
  destination_cidr_block = local.alb_subnet_cidrs[count.index]
  vpc_endpoint_id        = var.nfw_endpoint_ids[count.index]
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
    description = "HTTP from internet"
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

###############################################################
# Data sources
###############################################################
data "aws_region" "current" {}
