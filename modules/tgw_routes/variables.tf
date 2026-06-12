variable "core_route_table_id" {
  type = string
}

variable "spoke_route_table_id" {
  type = string
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

variable "tags" {
  type    = map(string)
  default = {}
}
