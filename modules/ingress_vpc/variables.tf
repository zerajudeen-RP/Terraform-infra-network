variable "name" { type = string }
variable "environment" { type = string }
variable "azs" { type = list(string) }
variable "tgw_id" { type = string }
variable "tgw_core_rt_id" { type = string }

variable "vpc_cidr" {
  description = "Ingress VPC CIDR — used as fallback if ipam_pool_id is empty"
  type        = string
  default     = "10.220.192.0/21"
}

variable "ipam_pool_id" {
  description = "IPAM pool ID for VPC CIDR allocation"
  type        = string
}

variable "ipam_netmask_length" {
  description = "Netmask length for IPAM allocation (e.g. 21 for /21)"
  type        = number
  default     = 21
}

variable "spoke_cidrs" {
  type    = list(string)
  default = []
}

variable "nfw_endpoint_ids" {
  description = "NFW endpoint IDs per AZ — injected from root after ingress_nfw is deployed"
  type        = list(string)
  default     = []
}

variable "tags" {
  type    = map(string)
  default = {}
}
