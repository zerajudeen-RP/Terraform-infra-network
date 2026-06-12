###############################################################
# Module: network_firewall
# Variables — AWS Network Firewall in the Inspect VPC
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
  description = "Inspect VPC ID"
}

variable "subnet_ids" {
  type        = list(string)
  description = "Firewall subnet IDs (one per AZ) — the existing firewall subnets in inspect VPC"
}

variable "azs" {
  type        = list(string)
  description = "Availability zones — must match order of subnet_ids"
}

###############################################################
# Stateless rule group — fast-path rules evaluated first
###############################################################

variable "stateless_default_actions" {
  type        = list(string)
  description = "Default action for packets not matching any stateless rule"
  default     = ["aws:forward_to_sfe"] # forward to stateful engine
}

variable "stateless_fragment_default_actions" {
  type        = list(string)
  description = "Default action for fragmented packets"
  default     = ["aws:forward_to_sfe"]
}

variable "stateless_rule_group_capacity" {
  type        = number
  description = "Capacity units for the stateless rule group (max 30000)"
  default     = 100
}

###############################################################
# Stateful rule group — Suricata-compatible IDS/IPS rules
###############################################################

variable "stateful_rule_group_capacity" {
  type        = number
  description = "Capacity units for the stateful rule group (max 30000)"
  default     = 1000
}

variable "stateful_default_actions" {
  type        = list(string)
  description = "Default actions for stateful engine (STRICT_ORDER mode)"
  default     = ["aws:drop_strict", "aws:alert_strict"]
}

variable "stateful_rule_order" {
  type        = string
  description = "Stateful rule evaluation order: DEFAULT_ACTION_ORDER or STRICT_ORDER"
  default     = "STRICT_ORDER"
}

###############################################################
# Home networks — suricata $HOME_NET variable
###############################################################
variable "home_net_cidrs" {
  type        = list(string)
  description = "RFC1918 / internal CIDR ranges for Suricata HOME_NET. Typically all spoke CIDRs + hub VPC CIDRs."
  default     = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]
}

###############################################################
# Allow-listed domains for egress (DNS-based FQDN filtering)
###############################################################
variable "allowed_domains" {
  type        = list(string)
  description = "FQDNs allowed for egress. Used in the stateful domain-list rule group."
  default = [
    ".amazonaws.com",
    ".cloudfront.net",
    ".s3.amazonaws.com",
    ".execute-api.ap-southeast-2.amazonaws.com",
  ]
}

variable "domain_list_rule_group_capacity" {
  type        = number
  description = "Capacity for the domain-list rule group"
  default     = 1000
}

###############################################################
# Firewall logging
###############################################################
variable "enable_alert_logging" {
  type        = bool
  description = "Enable alert log to CloudWatch Logs"
  default     = true
}

variable "enable_flow_logging" {
  type        = bool
  description = "Enable flow log to CloudWatch Logs"
  default     = true
}

variable "log_retention_days" {
  type        = number
  description = "CloudWatch log group retention in days"
  default     = 90
}

variable "tags" {
  type        = map(string)
  description = "Common resource tags"
  default     = {}
}
