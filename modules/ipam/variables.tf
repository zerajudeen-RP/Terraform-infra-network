variable "ipam_pool_id" {
  description = "ID of the existing IPAM pool (mct-au-network-pool). Find it in AWS Console → VPC → IPAM → Pools."
  type        = string
}

variable "region" {
  description = "AWS region — used for context only"
  type        = string
}

variable "environment" {
  description = "Environment name — used for context only"
  type        = string
}
