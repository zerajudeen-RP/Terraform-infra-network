###############################################################
# Module: ipam
# Simply looks up and exposes the existing IPAM pool ID/ARN.
# Each VPC allocates its own CIDR directly from the pool
# via ipv4_ipam_pool_id on the aws_vpc resource.
# No separate allocation resources needed here — doing so
# would create a second allocation and cause CIDR mismatch.
###############################################################

data "aws_vpc_ipam_pool" "this" {
  filter {
    name   = "ipam-pool-id"
    values = [var.ipam_pool_id]
  }
}
