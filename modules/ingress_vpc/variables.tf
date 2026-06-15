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

variable "nfw_endpoint_ids" {
  description = "Ordered list of NFW VPC endpoint IDs (one per AZ) — injected from root after ingress NFW is deployed"
  type        = list(string)
  default     = []
}

variable "gwlb_endpoint_service_name" {
  description = "Kept for interface compatibility — not used"
  type        = string
  default     = ""
}

variable "spoke_cidrs" {
  description = "Spoke VPC CIDRs — ALB routes traffic to these via TGW"
  type        = list(string)
  default     = []
}

variable "ipam_pool_id" {
  description = "IPAM pool ID — when set, VPC CIDR is assigned by IPAM"
  type        = string
  default     = ""
}

variable "ipam_netmask_length" {
  description = "Netmask length for IPAM VPC allocation"
  type        = number
  default     = 23
}

variable "tags" {
  type    = map(string)
  default = {}
}
