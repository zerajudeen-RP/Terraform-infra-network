variable "name" { type = string }
variable "environment" { type = string }
variable "azs" { type = list(string) }
variable "tgw_id" { type = string }
variable "tgw_core_rt_id" { type = string }

variable "vpc_cidr" {
  description = "Inspect VPC CIDR — all subnets calculated from this"
  type        = string
  default     = "10.220.200.0/22"
}

variable "ipam_pool_id" {
  description = "Set to empty string to use hardcoded vpc_cidr"
  type        = string
  default     = ""
}

variable "ipam_netmask_length" {
  type    = number
  default = 22
}

variable "tags" {
  type    = map(string)
  default = {}
}
