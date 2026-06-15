###############################################################
# Module: waf — Outputs
###############################################################

output "web_acl_arn" {
  description = "ARN of the WAF WebACL"
  value       = aws_wafv2_web_acl.this.arn
}

output "web_acl_id" {
  description = "ID of the WAF WebACL"
  value       = aws_wafv2_web_acl.this.id
}

output "web_acl_capacity" {
  description = "Current capacity units consumed by the WebACL"
  value       = aws_wafv2_web_acl.this.capacity
}

output "log_group_name" {
  description = "CloudWatch log group name for WAF logs (null if logging disabled)"
  value       = var.enable_logging ? aws_cloudwatch_log_group.waf[0].name : null
}
