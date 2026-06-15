###############################################################
# Module: alb
# Variables — Internal Application Load Balancer
###############################################################

variable "name" {
  type        = string
  description = "Project / deployment name prefix"
}

variable "environment" {
  type        = string
  description = "Environment name (e.g. stage, prod)"
}

variable "vpc_id" {
  type        = string
  description = "Ingress VPC ID"
}

variable "subnet_ids" {
  type        = list(string)
  description = "ALB subnet IDs (one per AZ) from the ingress VPC"
}

variable "security_group_id" {
  type        = string
  description = "Security group ID to attach to the ALB"
}

variable "certificate_arn" {
  type        = string
  description = "ACM certificate ARN for HTTPS listener on the ALB. Required if enable_https is true."
  default     = ""
}

variable "enable_https" {
  type        = bool
  description = "Create an HTTPS listener on port 443. Requires certificate_arn."
  default     = true
}

variable "http_redirect_to_https" {
  type        = bool
  description = "When true the HTTP/80 listener issues a 301 redirect to HTTPS. When false it forwards to the default target group."
  default     = true
}

variable "ssl_policy" {
  type        = string
  description = "ALB SSL/TLS security policy"
  default     = "ELBSecurityPolicy-TLS13-1-2-2021-06"
}

variable "enable_deletion_protection" {
  type        = bool
  description = "Prevent accidental deletion of the ALB"
  default     = false
}

variable "enable_http2" {
  type        = bool
  description = "Enable HTTP/2 on the ALB"
  default     = true
}

variable "idle_timeout" {
  type        = number
  description = "ALB idle connection timeout in seconds"
  default     = 60
}

variable "access_logs_bucket" {
  type        = string
  description = "S3 bucket for ALB access logs. Leave empty to disable."
  default     = ""
}

variable "access_logs_prefix" {
  type        = string
  description = "S3 prefix for ALB access logs."
  default     = "alb"
}

###############################################################
# Default target group (catch-all)
# Used for the default action on the HTTPS listener when no
# host/path rule matches. Typically points to a 404/maintenance
# backend or a maintenance page target group.
###############################################################
variable "default_target_group_port" {
  type        = number
  description = "Port for the default (catch-all) target group"
  default     = 80
}

variable "default_target_group_protocol" {
  type        = string
  description = "Protocol for the default (catch-all) target group (HTTP or HTTPS)"
  default     = "HTTP"
}

variable "default_target_group_type" {
  type        = string
  description = "Target type for the default target group: instance, ip, or lambda"
  default     = "ip"
}

variable "default_health_check_path" {
  type        = string
  description = "Health check path for the default target group"
  default     = "/"
}

variable "default_health_check_protocol" {
  type        = string
  description = "Health check protocol for the default target group"
  default     = "HTTP"
}

variable "default_health_check_matcher" {
  type        = string
  description = "HTTP response codes expected for a healthy target (e.g. '200' or '200-499')"
  default     = "200-499"
}

variable "default_health_check_interval" {
  type        = number
  description = "Health check interval in seconds"
  default     = 30
}

variable "default_health_check_timeout" {
  type        = number
  description = "Health check timeout in seconds"
  default     = 5
}

variable "default_health_check_healthy_threshold" {
  type        = number
  description = "Number of successful checks before marking healthy"
  default     = 3
}

variable "default_health_check_unhealthy_threshold" {
  type        = number
  description = "Number of failed checks before marking unhealthy"
  default     = 3
}

###############################################################
# Listener rules (host/path-based routing to spoke workloads)
###############################################################
variable "listener_rules" {
  description = <<-EOT
    List of listener rules for the ALB. Each rule forwards matching
    requests to a dedicated target group and optionally registers
    EC2 private IPs directly as targets.

    Each rule object:
      priority    : (number)       Rule priority — must be unique, lower = higher priority
      host_header : (list(string)) Optional host header patterns, e.g. ["api.example.com"]
      path_pattern: (list(string)) Optional path patterns, e.g. ["/api/*"]
      target_ips  : (list(string)) Optional EC2 private IPs to register as targets
      target_group: object {
        name                     : (string) Unique short name (used for TG resource name)
        port                     : (number) Target port
        protocol                 : (string) HTTP or HTTPS
        target_type              : (string) instance | ip | lambda
        health_check_path        : (string) Health check path
        health_check_protocol    : (string) HTTP or HTTPS
        health_check_matcher     : (string) Expected HTTP status code(s)
        health_check_interval    : (number) Interval in seconds
        health_check_timeout     : (number) Timeout in seconds
        healthy_threshold        : (number)
        unhealthy_threshold      : (number)
        stickiness_enabled       : (bool)   optional, defaults to false
        deregistration_delay     : (number) seconds, defaults to 300
      }
  EOT
  type = list(object({
    priority     = number
    host_header  = optional(list(string), [])
    path_pattern = optional(list(string), [])
    target_ips   = optional(list(string), [])
    target_group = object({
      name                  = string
      port                  = number
      protocol              = string
      target_type           = string
      health_check_path     = string
      health_check_protocol = string
      health_check_matcher  = string
      health_check_interval = number
      health_check_timeout  = number
      healthy_threshold     = number
      unhealthy_threshold   = number
      stickiness_enabled    = optional(bool, false)
      deregistration_delay  = optional(number, 300)
    })
  }))
  default = []
}

variable "tags" {
  type        = map(string)
  description = "Common resource tags"
  default     = {}
}
