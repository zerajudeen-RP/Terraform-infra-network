output "ipam_pool_id" {
  description = "IPAM pool ID — pass this to each VPC module"
  value       = data.aws_vpc_ipam_pool.this.id
}

output "ipam_pool_arn" {
  description = "IPAM pool ARN"
  value       = data.aws_vpc_ipam_pool.this.arn
}
