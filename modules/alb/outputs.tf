###############################################################
# Module: alb — Outputs
###############################################################

output "alb_arn" {
  description = "ARN of the internal ALB — pass to nlb module as alb_arn"
  value       = aws_lb.this.arn
}

output "alb_dns_name" {
  description = "Internal DNS name of the ALB"
  value       = aws_lb.this.dns_name
}

output "alb_zone_id" {
  description = "Hosted zone ID of the ALB — for Route53 alias records"
  value       = aws_lb.this.zone_id
}

output "alb_id" {
  description = "ID of the ALB"
  value       = aws_lb.this.id
}

output "http_listener_arn" {
  description = "ARN of the HTTP/80 listener"
  value       = aws_lb_listener.http.arn
}

output "https_listener_arn" {
  description = "ARN of the HTTPS/443 listener (null if enable_https = false)"
  value       = var.enable_https ? aws_lb_listener.https[0].arn : null
}

output "default_target_group_arn" {
  description = "ARN of the default (catch-all) target group"
  value       = aws_lb_target_group.default.arn
}

output "rule_target_group_arns" {
  description = "Map of rule name → target group ARN for all listener rule TGs"
  value       = { for k, v in aws_lb_target_group.rules : k => v.arn }
}

output "rule_target_group_names" {
  description = "Map of rule name → target group name"
  value       = { for k, v in aws_lb_target_group.rules : k => v.name }
}
