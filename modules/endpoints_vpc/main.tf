###############################################################
# Module: endpoints_vpc
# Centralized PrivateLink Interface Endpoints VPC
# CIDR: 10.220.134.0/23
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
    Name = "${var.name}-${var.environment}-endpoints-vpc"
  })
}

###############################################################
# Subnet CIDR calculations using cidrsubnet()
#
# VPC is a /23 (512 IPs).
# Endpoint subnets need to be large (/25 = 128 IPs) to fit
# all the interface endpoint ENIs (one per service per AZ).
# TGW attach subnets are /28 (16 IPs).
#
# Layout (newbits=1 gives /24, newbits=2 gives /25, newbits=5 gives /28):
#   AZ-a: 10.x.x.0/25   (first half of first /24)
#   AZ-b: 10.x.x+1.0/25 (first half of second /24)
#   AZ-c: 10.x.x+1.128/25 (second half of second /24)
#   TGW-a: carved from the upper half of AZ-a /24
#   TGW-b/c: carved from remaining space
###############################################################
locals {
  # Use actual IPAM-assigned VPC CIDR for subnet calculations
  vpc_cidr = aws_vpc.this.cidr_block

  # /25 endpoint subnets (newbits=2 from /23 = /25)
  endpoint_subnet_cidrs = [
    cidrsubnet(local.vpc_cidr, 2, 0), # AZ-a
    cidrsubnet(local.vpc_cidr, 2, 2), # AZ-b
    cidrsubnet(local.vpc_cidr, 2, 3), # AZ-c
  ]
  # /28 TGW attach subnets (newbits=5 from /23 = /28)
  tgw_subnet_cidrs = [
    cidrsubnet(local.vpc_cidr, 5, 8),  # AZ-a
    cidrsubnet(local.vpc_cidr, 5, 9),  # AZ-b
    cidrsubnet(local.vpc_cidr, 5, 10), # AZ-c
  ]
}

###############################################################
# Subnets — Interface Endpoints (one per AZ)
###############################################################
resource "aws_subnet" "endpoints" {
  count             = length(var.azs)
  vpc_id            = aws_vpc.this.id
  cidr_block        = local.endpoint_subnet_cidrs[count.index]
  availability_zone = var.azs[count.index]

  tags = merge(var.tags, {
    Name = "${var.name}-${var.environment}-endpoints-sub-${substr(var.azs[count.index], -1, 1)}"
    Tier = "endpoints"
  })
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
    Name = "${var.name}-${var.environment}-endpoints-tgw-${substr(var.azs[count.index], -1, 1)}"
    Tier = "tgw-attach"
  })
}

###############################################################
# Route Tables
###############################################################

# Endpoint subnet route tables — return traffic via TGW
resource "aws_route_table" "endpoints" {
  count  = length(var.azs)
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, {
    Name = "${var.name}-${var.environment}-endpoints-rt-${substr(var.azs[count.index], -1, 1)}"
  })
}

resource "aws_route_table_association" "endpoints" {
  count          = length(var.azs)
  subnet_id      = aws_subnet.endpoints[count.index].id
  route_table_id = aws_route_table.endpoints[count.index].id
}

resource "aws_route" "endpoints_to_tgw" {
  count                  = length(var.azs)
  route_table_id         = aws_route_table.endpoints[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  transit_gateway_id     = var.tgw_id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.this]
}

# TGW attachment subnet route tables
# Return traffic arriving from TGW destined for endpoint ENIs
# is handled by local routing. Add explicit local CIDR route.
resource "aws_route_table" "tgw" {
  count  = length(var.azs)
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, {
    Name = "${var.name}-${var.environment}-endpoints-rt-tgw-${substr(var.azs[count.index], -1, 1)}"
  })
}

resource "aws_route_table_association" "tgw" {
  count          = length(var.azs)
  subnet_id      = aws_subnet.tgw[count.index].id
  route_table_id = aws_route_table.tgw[count.index].id
}

# 0.0.0.0/0 → TGW so that any response from a TGW-attached subnet
# can reach back through TGW to the originating spoke VPC
resource "aws_route" "tgw_subnet_to_tgw" {
  count                  = length(var.azs)
  route_table_id         = aws_route_table.tgw[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  transit_gateway_id     = var.tgw_id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.this]
}

###############################################################
# S3 + DynamoDB Gateway Endpoints
###############################################################
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = aws_route_table.endpoints[*].id

  tags = merge(var.tags, {
    Name = "${var.name}-${var.environment}-endpoints-s3-gw"
  })
}

resource "aws_vpc_endpoint" "dynamodb" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.dynamodb"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = aws_route_table.endpoints[*].id

  tags = merge(var.tags, {
    Name = "${var.name}-${var.environment}-endpoints-dynamodb-gw"
  })
}

###############################################################
# Security Group for Interface Endpoints
# Allows HTTPS (443) from all spoke VPC CIDRs
###############################################################
resource "aws_security_group" "endpoints" {
  name        = "${var.name}-${var.environment}-endpoints-sg"
  description = "Allow HTTPS from spoke VPCs to interface endpoints"
  vpc_id      = aws_vpc.this.id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidrs
    description = "HTTPS from spoke VPCs"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.name}-${var.environment}-endpoints-sg"
  })
}

###############################################################
# Interface Endpoints
###############################################################
locals {
  interface_endpoints = [
    "ssm",
    "ssmmessages",
    "ec2messages",
    "ec2",
    "kms",
    "secretsmanager",
    "logs",
    "ecr.api",
    "ecr.dkr",
    "sts",
    "sns",
    "sqs",
    "monitoring",
    "events",
    "elasticloadbalancing",
    "autoscaling",
    "eks",
    "s3",
  ]
}

resource "aws_vpc_endpoint" "interface" {
  for_each = toset(local.interface_endpoints)

  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.${each.value}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.endpoints[*].id
  security_group_ids  = [aws_security_group.endpoints.id]
  private_dns_enabled = true

  tags = merge(var.tags, {
    Name = "${var.name}-${var.environment}-endpoint-${each.value}"
  })
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
    Name = "${var.name}-${var.environment}-endpoints-tgw-attach"
  })
}

# Associate endpoints VPC to core route table
resource "aws_ec2_transit_gateway_route_table_association" "this" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.this.id
  transit_gateway_route_table_id = var.tgw_core_rt_id
}

# Propagate endpoints VPC routes to both core and spoke route tables
# Spoke VPCs need to know how to reach the endpoints VPC
resource "aws_ec2_transit_gateway_route_table_propagation" "core" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.this.id
  transit_gateway_route_table_id = var.tgw_core_rt_id
}

resource "aws_ec2_transit_gateway_route_table_propagation" "spoke" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.this.id
  transit_gateway_route_table_id = var.tgw_spoke_rt_id
}

###############################################################
# Data sources
###############################################################
data "aws_region" "current" {}
