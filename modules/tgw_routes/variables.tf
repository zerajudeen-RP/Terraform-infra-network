variable "core_route_table_id" {
  type = string
}

variable "spoke_route_table_ids" {
  description = "List of spoke route table IDs (stage + prod)"
  type        = list(string)
}

variable "inspect_attachment_id" {
  type = string
}

variable "ingress_attachment_id" {
  type = string
}

variable "endpoints_attachment_id" {
  type = string
}

variable "spoke_cidrs" {
  type = list(string)
}

variable "inspect_vpc_cidr" {
  type = string
}

variable "endpoints_vpc_cidr" {
  type = string
}

variable "ingress_vpc_cidr" {
  type = string
}

variable "cross_account_routes" {
  description = <<-EOT
    List of cross-account routes that replace blackholes in spoke RTs.
    Each entry specifies a CIDR that should be routable (not blackholed)
    from a specific spoke RT, and the TGW attachment to route it to.
    Example: allow vendor VPC to reach shared-services VPC.
  EOT
  type = list(object({
    spoke_rt_id   = string  # Which spoke RT to add the route to
    cidr          = string  # Destination CIDR (must also exist in spoke_cidrs)
    attachment_id = string  # TGW attachment ID to route traffic to
  }))
  default = []
}

variable "tags" {
  type    = map(string)
  default = {}
}
