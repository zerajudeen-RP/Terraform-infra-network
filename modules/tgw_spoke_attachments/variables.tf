variable "tgw_spoke_rt_id" {
  description = "TGW spoke route table ID — lives in the hub account"
  type        = string
}

variable "spoke_attachment_ids" {
  description = "Map of workload name → TGW attachment ID. Get the attachment ID from the workload account after it applies. e.g. { stage-workload = 'tgw-attach-0abc123' }"
  type        = map(string)
  default     = {}
}

variable "tags" {
  type    = map(string)
  default = {}
}
