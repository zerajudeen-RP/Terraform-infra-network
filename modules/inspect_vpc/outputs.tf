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

output "gwlb_arn" {
  value = aws_lb.gwlb.arn
}

output "gwlb_endpoint_service_name" {
  value = aws_vpc_endpoint_service.gwlb.service_name
}

output "nat_gateway_ids" {
  value = aws_nat_gateway.this[*].id
}

output "nat_eip_public_ips" {
  value = aws_eip.nat[*].public_ip
}

output "tgw_subnet_ids" {
  value = aws_subnet.tgw[*].id
}

output "tgw_route_table_ids" {
  description = "TGW attachment subnet route table IDs — used by root to add NFW endpoint routes"
  value       = aws_route_table.tgw[*].id
}

output "firewall_subnet_ids" {
  value = aws_subnet.firewall[*].id
}

output "nat_subnet_ids" {
  value = aws_subnet.nat[*].id
}
