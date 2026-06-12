###############################################################
# Module: nlb
# Variables — Internet-facing Network Load Balancer
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
  description = "NLB subnet IDs (one per AZ) from the ingress VPC"
}

variable "security_group_id" {
  type        = string
  description = "Security group ID to attach to the NLB"
}

variable "alb_arn" {
  type        = string
  description = "ARN of the internal ALB to forward traffic to"
}

variable "alb_target_port" {
  type        = number
  description = "Port the ALB listens on (typically 443)"
  default     = 443
}

variable "http_port" {
  type        = number
  description = "HTTP listener port (redirect to HTTPS)"
  default     = 80
}

variable "https_port" {
  type        = number
  description = "HTTPS listener port"
  default     = 443
}

variable "certificate_arn" {
  type        = string
  description = "ACM certificate ARN for TLS termination on the NLB. Leave empty to skip TLS on NLB (passthrough to ALB)."
  default     = ""
}

variable "enable_cross_zone_load_balancing" {
  type        = bool
  description = "Enable cross-zone load balancing on the NLB"
  default     = true
}

variable "enable_deletion_protection" {
  type        = bool
  description = "Prevent accidental deletion of the NLB"
  default     = false
}

variable "idle_timeout" {
  type        = number
  description = "TCP idle timeout in seconds (NLBs don't use HTTP idle timeout)"
  default     = 60
}

variable "access_logs_bucket" {
  type        = string
  description = "S3 bucket for NLB access logs. Leave empty to disable."
  default     = ""
}

variable "access_logs_prefix" {
  type        = string
  description = "S3 prefix for NLB access logs."
  default     = "nlb"
}

variable "health_check_protocol" {
  type        = string
  description = "Health check protocol for the ALB target group (TCP or HTTPS)"
  default     = "TCP"
}

variable "health_check_port" {
  type        = string
  description = "Health check port. Use 'traffic-port' to use the target group port."
  default     = "traffic-port"
}

variable "health_check_interval" {
  type        = number
  description = "Health check interval in seconds (10 or 30 for NLB)"
  default     = 30
}

variable "health_check_healthy_threshold" {
  type        = number
  description = "Number of consecutive successful health checks before marking healthy"
  default     = 3
}

variable "health_check_unhealthy_threshold" {
  type        = number
  description = "Number of consecutive failed health checks before marking unhealthy"
  default     = 3
}

variable "tags" {
  type        = map(string)
  description = "Common resource tags"
  default     = {}
}
