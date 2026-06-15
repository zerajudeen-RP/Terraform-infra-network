variable "name" { type = string }
variable "environment" { type = string }

variable "vpc_id" {
  type        = string
  description = "Ingress VPC ID"
}

variable "subnet_ids" {
  type        = list(string)
  description = "Firewall subnet IDs in the ingress VPC (one per AZ)"
}

variable "azs" {
  type        = list(string)
  description = "Availability zones — must match order of subnet_ids"
}

variable "stateless_rule_group_capacity" {
  type    = number
  default = 100
}

variable "stateful_rule_group_capacity" {
  type    = number
  default = 1000
}

variable "enable_alert_logging" {
  type    = bool
  default = true
}

variable "enable_flow_logging" {
  type    = bool
  default = true
}

variable "log_retention_days" {
  type    = number
  default = 90
}

variable "tags" {
  type    = map(string)
  default = {}
}
