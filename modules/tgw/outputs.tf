output "tgw_id" {
  value = aws_ec2_transit_gateway.this.id
}

output "core_route_table_id" {
  value = aws_ec2_transit_gateway_route_table.core.id
}

output "spoke_route_table_id" {
  value = aws_ec2_transit_gateway_route_table.spoke.id
}
