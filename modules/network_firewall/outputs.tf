output "firewall_arn" { value = aws_networkfirewall_firewall.this.arn }
output "firewall_policy_arn" { value = aws_networkfirewall_firewall_policy.this.arn }
output "endpoint_ids" { value = local.endpoint_ids }
output "endpoint_by_az" { value = local.endpoint_by_az }
output "alert_log_group_name" { value = var.enable_alert_logging ? aws_cloudwatch_log_group.alert[0].name : null }
output "flow_log_group_name" { value = var.enable_flow_logging ? aws_cloudwatch_log_group.flow[0].name : null }
