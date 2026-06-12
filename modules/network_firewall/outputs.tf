###############################################################
# Module: network_firewall — Outputs
###############################################################

output "firewall_arn" {
  description = "ARN of the AWS Network Firewall"
  value       = aws_networkfirewall_firewall.this.arn
}

output "firewall_id" {
  description = "ID of the AWS Network Firewall"
  value       = aws_networkfirewall_firewall.this.id
}

output "firewall_policy_arn" {
  description = "ARN of the firewall policy"
  value       = aws_networkfirewall_firewall_policy.this.arn
}

output "endpoint_ids" {
  description = "Ordered list of Network Firewall VPC endpoint IDs — aligned with var.subnet_ids / var.azs"
  value       = local.endpoint_ids
}

output "endpoint_by_az" {
  description = "Map of AZ name → Network Firewall endpoint ID. Use this to create per-AZ route table entries."
  value       = local.endpoint_by_az
}

output "endpoint_by_subnet" {
  description = "Map of subnet ID → Network Firewall endpoint ID"
  value       = local.endpoint_by_subnet
}

output "stateless_rule_group_arn" {
  description = "ARN of the stateless rule group"
  value       = aws_networkfirewall_rule_group.stateless.arn
}

output "stateful_suricata_rule_group_arn" {
  description = "ARN of the stateful Suricata rule group"
  value       = aws_networkfirewall_rule_group.stateful_suricata.arn
}

output "stateful_domain_list_rule_group_arn" {
  description = "ARN of the stateful domain-list rule group"
  value       = aws_networkfirewall_rule_group.stateful_domain_list.arn
}

output "alert_log_group_name" {
  description = "CloudWatch log group name for firewall alerts (null if logging disabled)"
  value       = var.enable_alert_logging ? aws_cloudwatch_log_group.alert[0].name : null
}

output "flow_log_group_name" {
  description = "CloudWatch log group name for firewall flow logs (null if logging disabled)"
  value       = var.enable_flow_logging ? aws_cloudwatch_log_group.flow[0].name : null
}
