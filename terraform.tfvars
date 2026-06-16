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
# VPC CIDRs
###############################################################
ingress_vpc_cidr = "10.220.192.0/21"
inspect_vpc_cidr = "10.220.200.0/22"

###############################################################
# IPAM
###############################################################
# Update this list when workload VPCs are deployed.
# Used for TGW blackhole routes and endpoint security group rules.
###############################################################
spoke_cidrs = [
  "10.220.128.0/21"  # Stage workload VPC — placeholder until workload is deployed
]

spoke_attachment_ids = {
  "stage-workload" = "tgw-attach-0af4d927a43fe17c3"
}

###############################################################
# NLB
# nlb_certificate_arn — leave empty for TCP passthrough (ALB terminates TLS)
# lb_access_logs_bucket — leave empty to disable access logs
###############################################################
nlb_certificate_arn   = ""  # optional: "arn:aws:acm:ap-southeast-2:ACCOUNT:certificate/CERT-ID"
lb_access_logs_bucket = ""  # optional: "mct-au-lb-access-logs"

###############################################################
# ALB
# alb_certificate_arn is required for HTTPS listener.
# Replace with your ACM cert ARN after cert is issued.
###############################################################
alb_certificate_arn = ""  # required for HTTPS: "arn:aws:acm:ap-southeast-2:ACCOUNT:certificate/CERT-ID"
alb_ssl_policy      = "ELBSecurityPolicy-TLS13-1-2-2021-06"
alb_idle_timeout    = 60

# Listener rules — add entries per workload service.
# Example (uncomment and update when workloads are ready):
# alb_listener_rules = [
#   {
#     priority     = 10
#     host_header  = ["api.mct-au.example.com"]
#     path_pattern = ["/api/*"]
#     target_group = {
#       name                  = "api-svc"
#       port                  = 443
#       protocol              = "HTTPS"
#       target_type           = "ip"
#       health_check_path     = "/health"
#       health_check_protocol = "HTTPS"
#       health_check_matcher  = "200"
#       health_check_interval = 30
#       health_check_timeout  = 5
#       healthy_threshold     = 3
#       unhealthy_threshold   = 3
#       stickiness_enabled    = false
#       deregistration_delay  = 300
#     }
#   }
# ]
alb_listener_rules = [
  {
    priority     = 10
    host_header  = []
    path_pattern = ["/*"]
    target_ips   = ["10.220.128.99"]   # workload EC2 private IP
    target_group = {
      name                  = "workload-ec2"
      port                  = 80
      protocol              = "HTTP"
      target_type           = "ip"
      health_check_path     = "/"
      health_check_protocol = "HTTP"
      health_check_matcher  = "200-499"
      health_check_interval = 30
      health_check_timeout  = 5
      healthy_threshold     = 2
      unhealthy_threshold   = 2
      stickiness_enabled    = false
      deregistration_delay  = 30
    }
  }
]

###############################################################
# RAM — TGW sharing
# Add the 12-digit AWS account ID of each workload account.
###############################################################
workload_account_ids          = ["034866042265"]  # replace with real account ID
ram_allow_external_principals = true

###############################################################
# WAF
###############################################################
waf_rate_limit         = 2000
waf_log_retention_days = 90

###############################################################
# Network Firewall
###############################################################
nfw_allowed_domains = [
  ".amazonaws.com",
  ".cloudfront.net",
  ".s3.amazonaws.com",
  ".execute-api.ap-southeast-2.amazonaws.com",
]
nfw_log_retention_days            = 90
nfw_stateful_rule_order           = "STRICT_ORDER"
nfw_stateful_rule_group_capacity  = 1000
nfw_stateless_rule_group_capacity = 100
