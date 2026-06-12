variable "name" {
  type = string
}

variable "environment" {
  type = string
}

variable "vpc_cidr" {
  description = "VPC CIDR — only used when ipam_pool_id is empty. When IPAM is active, subnets use aws_vpc.this.cidr_block internally."
  type        = string
  default     = ""
}

variable "azs" {
  type = list(string)
}

variable "tgw_id" {
  type = string
}

variable "tgw_core_rt_id" {
  type = string
}

variable "ipam_pool_id" {
  description = "IPAM pool ID — when set, VPC CIDR is assigned by IPAM"
  type        = string
  default     = ""
}

variable "ipam_netmask_length" {
  description = "Netmask length for IPAM VPC allocation"
  type        = number
  default     = 22
}

variable "tags" {
  type    = map(string)
  default = {}
}
