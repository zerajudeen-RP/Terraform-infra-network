###############################################################
# Module: waf — Variables
###############################################################

variable "name" {
  type        = string
  description = "Project / deployment name prefix"
}

variable "environment" {
  type        = string
  description = "Environment name (e.g. stage, prod)"
}

variable "alb_arn" {
  type        = string
  description = "ARN of the ALB to associate the WAF WebACL with"
}

variable "rate_limit" {
  type        = number
  description = "Maximum requests per 5 minutes per IP before blocking"
  default     = 2000
}

variable "enable_logging" {
  type        = bool
  description = "Enable WAF logging to CloudWatch Logs"
  default     = true
}

variable "log_retention_days" {
  type        = number
  description = "CloudWatch log retention in days for WAF logs"
  default     = 90
}

variable "tags" {
  type        = map(string)
  description = "Common resource tags"
  default     = {}
}
