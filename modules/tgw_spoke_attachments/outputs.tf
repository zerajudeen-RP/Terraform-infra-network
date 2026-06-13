output "association_ids" {
  description = "Map of workload name → TGW route table association ID"
  value       = { for k, v in aws_ec2_transit_gateway_route_table_association.spoke : k => v.id }
}

output "propagation_ids" {
  description = "Map of workload name → TGW route table propagation ID"
  value       = { for k, v in aws_ec2_transit_gateway_route_table_propagation.spoke : k => v.id }
}
