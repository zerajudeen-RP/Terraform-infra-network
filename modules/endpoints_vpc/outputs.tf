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

output "endpoint_subnet_ids" {
  value = aws_subnet.endpoints[*].id
}

output "tgw_subnet_ids" {
  value = aws_subnet.tgw[*].id
}

output "endpoint_security_group_id" {
  value = aws_security_group.endpoints.id
}

output "interface_endpoint_ids" {
  value = { for k, v in aws_vpc_endpoint.interface : k => v.id }
}
