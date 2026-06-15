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

output "firewall_subnet_ids" {
  description = "Firewall subnet IDs — pass to ingress NFW module"
  value       = aws_subnet.firewall[*].id
}

output "alb_subnet_ids" {
  value = aws_subnet.alb[*].id
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

output "igw_edge_route_table_ids" {
  description = "IGW edge route table ID — used by root to add NFW endpoint routes"
  value       = [aws_route_table.igw_edge.id]
}
