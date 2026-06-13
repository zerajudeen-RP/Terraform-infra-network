###############################################################
# Module: ram — Outputs
###############################################################

output "resource_share_arn" {
  description = "ARN of the RAM resource share"
  value       = aws_ram_resource_share.tgw.arn
}

output "resource_share_id" {
  description = "ID of the RAM resource share"
  value       = aws_ram_resource_share.tgw.id
}

output "principal_associations" {
  description = "Map of account ID → RAM principal association ARN"
  value       = { for k, v in aws_ram_principal_association.workload_accounts : k => v.id }
}
