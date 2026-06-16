###############################################################
# Module: ingress_vpc
# Centralized Ingress VPC — multi-environment (demo, stage, prod)
# VPC CIDR: var.vpc_cidr (default 10.220.192.0/21)
#
# All subnet CIDRs are calculated using cidrsubnet().
# Change vpc_cidr and everything recalculates automatically.
#
# Layout for a /21 (2048 IPs):
#   - Demo  ALB: 3× /27 (slots 0-2)    = 96 IPs
#   - Demo  NLB: 3× /27 (slots 3-5)    = 96 IPs
#   - Stage ALB: 3× /27 (slots 6-8)    = 96 IPs
#   - Stage NLB: 3× /27 (slots 9-11)   = 96 IPs
#   - Firewall:  3× /27 (slots 12-14)  = 96 IPs
#   - Prod  ALB: 3× /25 (slots 0-2 in upper half)  = 384 IPs
#   - Prod  NLB: 3× /25 (slots 3-5 in upper half)  = 384 IPs
#   - TGW:       3× /28 (slots from remaining)     = 48 IPs
#
# Approach:
#   Split the /21 into two /22 halves:
#     Lower /22: demo(/27), stage(/27), firewall(/27), TGW(/28)
#     Upper /22: prod ALB(/25), prod NLB(/25)
###############################################################

###############################################################
# VPC
###############################################################
resource "aws_vpc" "this" {
  ipv4_ipam_pool_id   = var.ipam_pool_id
  ipv4_netmask_length = var.ipam_netmask_length

  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(var.tags, { Name = "${var.name}-ingress-vpc" })
}

###############################################################
# Internet Gateway
###############################################################
resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = merge(var.tags, { Name = "${var.name}-ingress-igw" })
}

###############################################################
# Subnet CIDR calculations
#
# VPC /21 split into:
#   lower_half = cidrsubnet(vpc_cidr, 1, 0)  → first /22
#   upper_half = cidrsubnet(vpc_cidr, 1, 1)  → second /22
#
# Lower /22 — /27 subnets (newbits=5 from /22 → /27)
#   Slot layout: 0-2 demo ALB, 3-5 demo NLB, 6-8 stage ALB,
#                9-11 stage NLB, 12-14 firewall
#   /28 subnets (newbits=6 from /22 → /28): slots 30-32 TGW
#
# Upper /22 — /25 subnets (newbits=3 from /22 → /25)
#   Slots 0-2 prod ALB, slots 3-5 prod NLB
###############################################################
locals {
  lower_half = cidrsubnet(aws_vpc.this.cidr_block, 1, 0) # First /22
  upper_half = cidrsubnet(aws_vpc.this.cidr_block, 1, 1) # Second /22

  # /27 subnets from lower /22 (newbits=5)
  alb_demo_cidrs = [
    cidrsubnet(local.lower_half, 5, 0),
    cidrsubnet(local.lower_half, 5, 1),
    cidrsubnet(local.lower_half, 5, 2),
  ]
  nlb_demo_cidrs = [
    cidrsubnet(local.lower_half, 5, 3),
    cidrsubnet(local.lower_half, 5, 4),
    cidrsubnet(local.lower_half, 5, 5),
  ]
  alb_stage_cidrs = [
    cidrsubnet(local.lower_half, 5, 6),
    cidrsubnet(local.lower_half, 5, 7),
    cidrsubnet(local.lower_half, 5, 8),
  ]
  nlb_stage_cidrs = [
    cidrsubnet(local.lower_half, 5, 9),
    cidrsubnet(local.lower_half, 5, 10),
    cidrsubnet(local.lower_half, 5, 11),
  ]
  firewall_cidrs = [
    cidrsubnet(local.lower_half, 5, 12),
    cidrsubnet(local.lower_half, 5, 13),
    cidrsubnet(local.lower_half, 5, 14),
  ]
  # /28 TGW subnets from lower /22 (newbits=6)
  tgw_cidrs = [
    cidrsubnet(local.lower_half, 6, 30),
    cidrsubnet(local.lower_half, 6, 31),
    cidrsubnet(local.lower_half, 6, 32),
  ]

  # /25 subnets from upper /22 (newbits=3)
  alb_prod_cidrs = [
    cidrsubnet(local.upper_half, 3, 0),
    cidrsubnet(local.upper_half, 3, 1),
    cidrsubnet(local.upper_half, 3, 2),
  ]
  nlb_prod_cidrs = [
    cidrsubnet(local.upper_half, 3, 3),
    cidrsubnet(local.upper_half, 3, 4),
    cidrsubnet(local.upper_half, 3, 5),
  ]
}

###############################################################
# Subnets
###############################################################
resource "aws_subnet" "alb_demo" {
  count             = length(var.azs)
  vpc_id            = aws_vpc.this.id
  cidr_block        = local.alb_demo_cidrs[count.index]
  availability_zone = var.azs[count.index]
  tags = merge(var.tags, { Name = "${var.name}-ingress-alb-demo-${substr(var.azs[count.index], -1, 1)}", Tier = "alb", Env = "demo" })
}

resource "aws_subnet" "nlb_demo" {
  count             = length(var.azs)
  vpc_id            = aws_vpc.this.id
  cidr_block        = local.nlb_demo_cidrs[count.index]
  availability_zone = var.azs[count.index]
  tags = merge(var.tags, { Name = "${var.name}-ingress-nlb-demo-${substr(var.azs[count.index], -1, 1)}", Tier = "nlb", Env = "demo" })
}

resource "aws_subnet" "alb_stage" {
  count             = length(var.azs)
  vpc_id            = aws_vpc.this.id
  cidr_block        = local.alb_stage_cidrs[count.index]
  availability_zone = var.azs[count.index]
  tags = merge(var.tags, { Name = "${var.name}-ingress-alb-stage-${substr(var.azs[count.index], -1, 1)}", Tier = "alb", Env = "stage" })
}

resource "aws_subnet" "nlb_stage" {
  count             = length(var.azs)
  vpc_id            = aws_vpc.this.id
  cidr_block        = local.nlb_stage_cidrs[count.index]
  availability_zone = var.azs[count.index]
  tags = merge(var.tags, { Name = "${var.name}-ingress-nlb-stage-${substr(var.azs[count.index], -1, 1)}", Tier = "nlb", Env = "stage" })
}

resource "aws_subnet" "alb_prod" {
  count             = length(var.azs)
  vpc_id            = aws_vpc.this.id
  cidr_block        = local.alb_prod_cidrs[count.index]
  availability_zone = var.azs[count.index]
  tags = merge(var.tags, { Name = "${var.name}-ingress-alb-prod-${substr(var.azs[count.index], -1, 1)}", Tier = "alb", Env = "prod" })
}

resource "aws_subnet" "nlb_prod" {
  count             = length(var.azs)
  vpc_id            = aws_vpc.this.id
  cidr_block        = local.nlb_prod_cidrs[count.index]
  availability_zone = var.azs[count.index]
  tags = merge(var.tags, { Name = "${var.name}-ingress-nlb-prod-${substr(var.azs[count.index], -1, 1)}", Tier = "nlb", Env = "prod" })
}

resource "aws_subnet" "firewall" {
  count             = length(var.azs)
  vpc_id            = aws_vpc.this.id
  cidr_block        = local.firewall_cidrs[count.index]
  availability_zone = var.azs[count.index]
  tags = merge(var.tags, { Name = "${var.name}-ingress-fw-${substr(var.azs[count.index], -1, 1)}", Tier = "firewall" })
}

resource "aws_subnet" "tgw" {
  count             = length(var.azs)
  vpc_id            = aws_vpc.this.id
  cidr_block        = local.tgw_cidrs[count.index]
  availability_zone = var.azs[count.index]
  tags = merge(var.tags, { Name = "${var.name}-ingress-tgw-${substr(var.azs[count.index], -1, 1)}", Tier = "tgw-attach" })
}

###############################################################
# IGW Edge Route Table
###############################################################
resource "aws_route_table" "igw_edge" {
  vpc_id = aws_vpc.this.id
  tags   = merge(var.tags, { Name = "${var.name}-ingress-rt-igw-edge" })
}

resource "aws_route_table_association" "igw_edge" {
  gateway_id     = aws_internet_gateway.this.id
  route_table_id = aws_route_table.igw_edge.id
}

# All NLB/ALB CIDRs → NFW endpoint per AZ
resource "aws_route" "igw_to_nfw_nlb_demo" {
  count                  = length(var.azs)
  route_table_id         = aws_route_table.igw_edge.id
  destination_cidr_block = local.nlb_demo_cidrs[count.index]
  vpc_endpoint_id        = var.nfw_endpoint_ids[count.index]
}
resource "aws_route" "igw_to_nfw_alb_demo" {
  count                  = length(var.azs)
  route_table_id         = aws_route_table.igw_edge.id
  destination_cidr_block = local.alb_demo_cidrs[count.index]
  vpc_endpoint_id        = var.nfw_endpoint_ids[count.index]
}
resource "aws_route" "igw_to_nfw_nlb_stage" {
  count                  = length(var.azs)
  route_table_id         = aws_route_table.igw_edge.id
  destination_cidr_block = local.nlb_stage_cidrs[count.index]
  vpc_endpoint_id        = var.nfw_endpoint_ids[count.index]
}
resource "aws_route" "igw_to_nfw_alb_stage" {
  count                  = length(var.azs)
  route_table_id         = aws_route_table.igw_edge.id
  destination_cidr_block = local.alb_stage_cidrs[count.index]
  vpc_endpoint_id        = var.nfw_endpoint_ids[count.index]
}
resource "aws_route" "igw_to_nfw_nlb_prod" {
  count                  = length(var.azs)
  route_table_id         = aws_route_table.igw_edge.id
  destination_cidr_block = local.nlb_prod_cidrs[count.index]
  vpc_endpoint_id        = var.nfw_endpoint_ids[count.index]
}
resource "aws_route" "igw_to_nfw_alb_prod" {
  count                  = length(var.azs)
  route_table_id         = aws_route_table.igw_edge.id
  destination_cidr_block = local.alb_prod_cidrs[count.index]
  vpc_endpoint_id        = var.nfw_endpoint_ids[count.index]
}

###############################################################
# Firewall RT — post-inspection → IGW
###############################################################
resource "aws_route_table" "firewall" {
  count  = length(var.azs)
  vpc_id = aws_vpc.this.id
  tags   = merge(var.tags, { Name = "${var.name}-ingress-rt-fw-${substr(var.azs[count.index], -1, 1)}" })
}
resource "aws_route_table_association" "firewall" {
  count          = length(var.azs)
  subnet_id      = aws_subnet.firewall[count.index].id
  route_table_id = aws_route_table.firewall[count.index].id
}
resource "aws_route" "firewall_to_igw" {
  count                  = length(var.azs)
  route_table_id         = aws_route_table.firewall[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

###############################################################
# NLB RT — return → NFW (shared across envs per AZ)
###############################################################
resource "aws_route_table" "nlb" {
  count  = length(var.azs)
  vpc_id = aws_vpc.this.id
  tags   = merge(var.tags, { Name = "${var.name}-ingress-rt-nlb-${substr(var.azs[count.index], -1, 1)}" })
}
resource "aws_route_table_association" "nlb_demo" {
  count          = length(var.azs)
  subnet_id      = aws_subnet.nlb_demo[count.index].id
  route_table_id = aws_route_table.nlb[count.index].id
}
resource "aws_route_table_association" "nlb_stage" {
  count          = length(var.azs)
  subnet_id      = aws_subnet.nlb_stage[count.index].id
  route_table_id = aws_route_table.nlb[count.index].id
}
resource "aws_route_table_association" "nlb_prod" {
  count          = length(var.azs)
  subnet_id      = aws_subnet.nlb_prod[count.index].id
  route_table_id = aws_route_table.nlb[count.index].id
}
resource "aws_route" "nlb_to_nfw" {
  count                  = length(var.azs)
  route_table_id         = aws_route_table.nlb[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  vpc_endpoint_id        = var.nfw_endpoint_ids[count.index]
}

###############################################################
# ALB RT — spoke → TGW, return → NFW (shared across envs per AZ)
###############################################################
resource "aws_route_table" "alb" {
  count  = length(var.azs)
  vpc_id = aws_vpc.this.id
  tags   = merge(var.tags, { Name = "${var.name}-ingress-rt-alb-${substr(var.azs[count.index], -1, 1)}" })
}
resource "aws_route_table_association" "alb_demo" {
  count          = length(var.azs)
  subnet_id      = aws_subnet.alb_demo[count.index].id
  route_table_id = aws_route_table.alb[count.index].id
}
resource "aws_route_table_association" "alb_stage" {
  count          = length(var.azs)
  subnet_id      = aws_subnet.alb_stage[count.index].id
  route_table_id = aws_route_table.alb[count.index].id
}
resource "aws_route_table_association" "alb_prod" {
  count          = length(var.azs)
  subnet_id      = aws_subnet.alb_prod[count.index].id
  route_table_id = aws_route_table.alb[count.index].id
}
resource "aws_route" "alb_to_nfw" {
  count                  = length(var.azs)
  route_table_id         = aws_route_table.alb[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  vpc_endpoint_id        = var.nfw_endpoint_ids[count.index]
}
resource "aws_route" "alb_to_tgw" {
  count                  = length(var.spoke_cidrs)
  route_table_id         = aws_route_table.alb[0].id
  destination_cidr_block = var.spoke_cidrs[count.index]
  transit_gateway_id     = var.tgw_id
  depends_on             = [aws_ec2_transit_gateway_vpc_attachment.this]
}
resource "aws_route" "alb_to_tgw_b" {
  count                  = length(var.spoke_cidrs)
  route_table_id         = aws_route_table.alb[1].id
  destination_cidr_block = var.spoke_cidrs[count.index]
  transit_gateway_id     = var.tgw_id
  depends_on             = [aws_ec2_transit_gateway_vpc_attachment.this]
}
resource "aws_route" "alb_to_tgw_c" {
  count                  = length(var.spoke_cidrs)
  route_table_id         = aws_route_table.alb[2].id
  destination_cidr_block = var.spoke_cidrs[count.index]
  transit_gateway_id     = var.tgw_id
  depends_on             = [aws_ec2_transit_gateway_vpc_attachment.this]
}

###############################################################
# TGW RT — traffic from workload → NFW for inspection
###############################################################
resource "aws_route_table" "tgw" {
  count  = length(var.azs)
  vpc_id = aws_vpc.this.id
  tags   = merge(var.tags, { Name = "${var.name}-ingress-rt-tgw-${substr(var.azs[count.index], -1, 1)}" })
}
resource "aws_route_table_association" "tgw" {
  count          = length(var.azs)
  subnet_id      = aws_subnet.tgw[count.index].id
  route_table_id = aws_route_table.tgw[count.index].id
}
# Route all NLB/ALB CIDRs from TGW subnet → NFW
resource "aws_route" "tgw_to_nfw_nlb_demo" {
  count                  = length(var.azs)
  route_table_id         = aws_route_table.tgw[count.index].id
  destination_cidr_block = local.nlb_demo_cidrs[count.index]
  vpc_endpoint_id        = var.nfw_endpoint_ids[count.index]
}
resource "aws_route" "tgw_to_nfw_alb_demo" {
  count                  = length(var.azs)
  route_table_id         = aws_route_table.tgw[count.index].id
  destination_cidr_block = local.alb_demo_cidrs[count.index]
  vpc_endpoint_id        = var.nfw_endpoint_ids[count.index]
}
resource "aws_route" "tgw_to_nfw_nlb_stage" {
  count                  = length(var.azs)
  route_table_id         = aws_route_table.tgw[count.index].id
  destination_cidr_block = local.nlb_stage_cidrs[count.index]
  vpc_endpoint_id        = var.nfw_endpoint_ids[count.index]
}
resource "aws_route" "tgw_to_nfw_alb_stage" {
  count                  = length(var.azs)
  route_table_id         = aws_route_table.tgw[count.index].id
  destination_cidr_block = local.alb_stage_cidrs[count.index]
  vpc_endpoint_id        = var.nfw_endpoint_ids[count.index]
}
resource "aws_route" "tgw_to_nfw_nlb_prod" {
  count                  = length(var.azs)
  route_table_id         = aws_route_table.tgw[count.index].id
  destination_cidr_block = local.nlb_prod_cidrs[count.index]
  vpc_endpoint_id        = var.nfw_endpoint_ids[count.index]
}
resource "aws_route" "tgw_to_nfw_alb_prod" {
  count                  = length(var.azs)
  route_table_id         = aws_route_table.tgw[count.index].id
  destination_cidr_block = local.alb_prod_cidrs[count.index]
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
  tags = merge(var.tags, { Name = "${var.name}-ingress-tgw-attach" })
}

resource "aws_ec2_transit_gateway_route_table_association" "this" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.this.id
  transit_gateway_route_table_id = var.tgw_core_rt_id
}

###############################################################
# Security Groups
###############################################################
resource "aws_security_group" "nlb" {
  name        = "${var.name}-ingress-nlb-sg"
  description = "NLB - allow inbound HTTPS/HTTP from internet"
  vpc_id      = aws_vpc.this.id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS"
  }
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTP"
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = merge(var.tags, { Name = "${var.name}-ingress-nlb-sg" })
}

resource "aws_security_group" "alb" {
  name        = "${var.name}-ingress-alb-sg"
  description = "ALB - allow inbound only from NLB security group"
  vpc_id      = aws_vpc.this.id

  ingress {
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.nlb.id]
    description     = "HTTPS from NLB"
  }
  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.nlb.id]
    description     = "HTTP from NLB"
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = merge(var.tags, { Name = "${var.name}-ingress-alb-sg" })
}
