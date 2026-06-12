###############################################################
# MCT Australia Stage — Network Hub
# Region: ap-southeast-2 (Sydney)
# IPAM Pool: mct-au-network-pool (10.220.192.0/19)
#
# VPC CIDRs are allocated dynamically by AWS IPAM at apply time.
# Subnets are carved from those VPC CIDRs using cidrsubnet()
# inside each module — no hardcoded IPs needed here.
###############################################################

region      = "ap-southeast-2"
name        = "mct-au"
environment = "stage"
tgw_asn     = 65522

# IPAM pool name tag — must match the existing pool in AWS
#ipam_pool_name = "mct-au-network-pool"
ipam_pool_id = "ipam-pool-03ed8297568d4c895"
azs = [
  "ap-southeast-2a",
  "ap-southeast-2b",
  "ap-southeast-2c"
]

###############################################################
# Spoke CIDRs (workload VPCs)
# Update this list when workload VPCs are deployed.
# Used for TGW blackhole routes and endpoint security group rules.
###############################################################
spoke_cidrs = [
  "10.220.136.0/21"  # Stage workload VPC — placeholder until workload is deployed
]
