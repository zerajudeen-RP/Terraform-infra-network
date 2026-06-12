###############################################################
# Module: nlb — Outputs
###############################################################

output "nlb_arn" {
  description = "ARN of the internet-facing NLB"
  value       = aws_lb.this.arn
}

output "nlb_dns_name" {
  description = "DNS name of the NLB — use this in Route53 alias records"
  value       = aws_lb.this.dns_name
}

output "nlb_zone_id" {
  description = "Hosted zone ID of the NLB — required for Route53 alias target"
  value       = aws_lb.this.zone_id
}

output "nlb_id" {
  description = "ID of the NLB"
  value       = aws_lb.this.id
}

output "alb_target_group_arn" {
  description = "ARN of the target group pointing to the ALB"
  value       = aws_lb_target_group.alb.arn
}

output "https_listener_arn" {
  description = "ARN of the HTTPS/TLS listener"
  value       = aws_lb_listener.https.arn
}

output "http_listener_arn" {
  description = "ARN of the HTTP listener"
  value       = aws_lb_listener.http.arn
}
