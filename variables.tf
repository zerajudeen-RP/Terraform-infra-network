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
