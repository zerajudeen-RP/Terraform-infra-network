variable "name" { type = string }
variable "environment" { type = string }

variable "domain_name" {
  description = "Domain name for the certificate (e.g. stage.au.mosaiclinical.ai)"
  type        = string
}

variable "zone_id" {
  description = "Route53 hosted zone ID for DNS validation records"
  type        = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
