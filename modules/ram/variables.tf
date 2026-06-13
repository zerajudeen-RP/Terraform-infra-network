###############################################################
# Module: ram — Variables
###############################################################

variable "name" {
  type        = string
  description = "Project / deployment name prefix"
}

variable "environment" {
  type        = string
  description = "Environment name"
}

variable "tgw_arn" {
  type        = string
  description = "ARN of the Transit Gateway to share"
}

variable "workload_account_ids" {
  type        = list(string)
  description = "List of workload AWS account IDs to share the TGW with"
}

variable "allow_external_principals" {
  type        = bool
  description = "Allow principals outside the AWS Organization. Set true when workload accounts are in a different org/not using AWS Organizations."
  default     = true
}

variable "tags" {
  type        = map(string)
  description = "Common resource tags"
  default     = {}
}
