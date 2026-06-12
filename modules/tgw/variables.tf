variable "name" {
  type = string
}

variable "environment" {
  type = string
}

variable "asn" {
  type    = number
  default = 65522
}

variable "tags" {
  type    = map(string)
  default = {}
}
