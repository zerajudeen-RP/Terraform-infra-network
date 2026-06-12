output "vpc_id" {
  value = aws_vpc.this.id
}

output "vpc_cidr_block" {
  description = "The actual CIDR block assigned to this VPC by IPAM"
  value       = aws_vpc.this.cidr_block
}

output "tgw_attachment_id" {
  value = aws_ec2_transit_gateway_vpc_attachment.this.id
}

output "nlb_subnet_ids" {
  value = aws_subnet.nlb[*].id
}

output "alb_subnet_ids" {
  value = aws_subnet.alb[*].id
}

output "gwlbe_subnet_ids" {
  value = aws_subnet.gwlbe[*].id
}

output "tgw_subnet_ids" {
  value = aws_subnet.tgw[*].id
}

output "nlb_security_group_id" {
  value = aws_security_group.nlb.id
}

output "alb_security_group_id" {
  value = aws_security_group.alb.id
}

output "internet_gateway_id" {
  value = aws_internet_gateway.this.id
}
