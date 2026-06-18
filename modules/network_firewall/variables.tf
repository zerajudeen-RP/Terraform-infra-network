variable "name" { type = string }
variable "environment" { type = string }
variable "vpc_id" { type = string }
variable "subnet_ids" { type = list(string) }
variable "azs" { type = list(string) }

variable "stateful_rule_group_capacity" {
  type    = number
  default = 10000
}

variable "home_net_cidrs" {
  type    = list(string)
  default = ["10.220.0.0/16"]
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
