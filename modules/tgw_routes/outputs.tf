output "spoke_default_route_id" {
  value = aws_ec2_transit_gateway_route.spoke_default_to_inspect.id
}

output "spoke_to_endpoints_route_id" {
  value = aws_ec2_transit_gateway_route.spoke_to_endpoints.id
}
