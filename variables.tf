###############################################################
# Root Variables
###############################################################

variable "region" {
  description = "AWS region"
  type        = string
  default     = "ap-southeast-2"
}

variable "name" {
  description = "Project / deployment name prefix"
  type        = string
  default     = "mct-au"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "stage"
}

variable "tgw_asn" {
  description = "BGP ASN for the Transit Gateway (must not conflict with us-east-1 TGW ASN 65521)"
  type        = number
  default     = 65522
}

variable "azs" {
  description = "Availability zones in ap-southeast-2"
  type        = list(string)
  default     = ["ap-southeast-2a", "ap-southeast-2b", "ap-southeast-2c"]
}

###############################################################
# IPAM
###############################################################
variable "ipam_pool_id" {
  description = "Name tag of the existing IPAM pool to allocate VPC CIDRs from"
  type        = string
  default = "ipam-pool-03ed8297568d4c895"

}

###############################################################
# Spoke CIDRs
# VPC CIDRs of workload accounts that attach to the TGW.
# Used for TGW blackhole routes and endpoint SG ingress rules.
###############################################################
variable "spoke_cidrs" {
  description = "List of spoke/workload VPC CIDRs"
  type        = list(string)
  default     = ["10.220.136.0/21"]
}

###############################################################
# NLB
###############################################################
variable "nlb_certificate_arn" {
  description = "ACM certificate ARN for TLS on the NLB. Leave empty for TCP passthrough (ALB handles TLS)."
  type        = string
  default     = ""
}

variable "lb_access_logs_bucket" {
  description = "S3 bucket name for NLB and ALB access logs. Leave empty to disable."
  type        = string
  default     = ""
}

###############################################################
# ALB
###############################################################
variable "alb_certificate_arn" {
  description = "ACM certificate ARN for HTTPS on the ALB. Required for HTTPS listener."
  type        = string
  default     = ""
}

variable "alb_ssl_policy" {
  description = "ALB SSL/TLS security policy"
  type        = string
  default     = "ELBSecurityPolicy-TLS13-1-2-2021-06"
}

variable "alb_idle_timeout" {
  description = "ALB idle connection timeout in seconds"
  type        = number
  default     = 60
}

variable "alb_listener_rules" {
  description = "ALB listener rules for host/path-based routing to spoke workloads. See alb module variables for schema."
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

###############################################################
# RAM — TGW sharing
###############################################################
variable "workload_account_ids" {
  description = "List of workload AWS account IDs to share the TGW with via RAM"
  type        = list(string)
  default     = []
}

variable "ram_allow_external_principals" {
  description = "Set true if workload accounts are outside your AWS Organization"
  type        = bool
  default     = true
}

###############################################################
# TGW spoke attachments — cross-account RT wiring
# Populated after workload account applies and tgw_attachment_id
# is known. Get it from: terraform output -state=workload tgw_attachment_id
###############################################################
variable "spoke_attachment_ids" {
  description = "Map of workload name to TGW attachment ID for cross-account RT association/propagation. e.g. { stage-workload = 'tgw-attach-0abc123' }"
  type        = map(string)
  default     = {}
}

###############################################################
# WAF
###############################################################
variable "waf_rate_limit" {
  description = "Max requests per 5 minutes per IP before WAF blocks the source"
  type        = number
  default     = 2000
}

variable "waf_log_retention_days" {
  description = "CloudWatch log retention in days for WAF logs"
  type        = number
  default     = 90
}

variable "nfw_allowed_domains" {
  description = "FQDNs allowlisted for egress through Network Firewall"
  type        = list(string)
  default = [
    ".amazonaws.com",
    ".cloudfront.net",
    ".s3.amazonaws.com",
    ".execute-api.ap-southeast-2.amazonaws.com",
  ]
}

variable "nfw_log_retention_days" {
  description = "CloudWatch log retention in days for Network Firewall logs"
  type        = number
  default     = 90
}

variable "nfw_stateful_rule_order" {
  description = "Stateful rule evaluation order: STRICT_ORDER or DEFAULT_ACTION_ORDER"
  type        = string
  default     = "STRICT_ORDER"
}

variable "nfw_stateful_rule_group_capacity" {
  description = "Capacity units for the stateful Suricata rule group"
  type        = number
  default     = 1000
}

variable "nfw_stateless_rule_group_capacity" {
  description = "Capacity units for the stateless rule group"
  type        = number
  default     = 100
}
