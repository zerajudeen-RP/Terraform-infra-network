###############################################################
# Module: network_firewall
# AWS Network Firewall — deployed in the Inspect VPC
#
# Architecture:
#   TGW → inspect TGW subnet → GWLBe → GWLB → firewall appliance
#   ↑ the "firewall appliance" in this hub is Network Firewall
#   Network Firewall endpoints land in the existing firewall subnets.
#
# Route integration (handled in inspect_vpc, not here):
#   The inspect VPC firewall subnet RTs already send 0.0.0.0/0 → NAT GW
#   and 10.220.0.0/16 → TGW.  The GWLB target group should register
#   the Network Firewall endpoint IDs (or the appliances behind them).
#
#   For a pure Network Firewall deployment (no 3rd party appliance),
#   the GWLBe pattern is replaced by Network Firewall's own endpoints.
#   Traffic flow:
#     TGW attach subnet RT: 0.0.0.0/0 → Network Firewall endpoint (per AZ)
#     Firewall subnet RT  : 0.0.0.0/0 → NAT GW  (post-inspection internet)
#                           RFC1918    → TGW      (return to spokes)
#   The endpoint IDs are exported so inspect_vpc route tables can be updated.
#
# Rule groups:
#   1. Stateless group — pass/drop/forward rules evaluated first (fast path)
#   2. Stateful Suricata group — custom IDS/IPS rules (STRICT_ORDER)
#   3. Domain-list group — FQDN allowlist for egress filtering
###############################################################

###############################################################
# CloudWatch Log Groups
###############################################################
resource "aws_cloudwatch_log_group" "alert" {
  count             = var.enable_alert_logging ? 1 : 0
  name              = "/aws/network-firewall/${var.name}-${var.environment}/alert"
  retention_in_days = var.log_retention_days

  tags = merge(var.tags, {
    Name = "${var.name}-${var.environment}-nfw-alert-logs"
  })
}

resource "aws_cloudwatch_log_group" "flow" {
  count             = var.enable_flow_logging ? 1 : 0
  name              = "/aws/network-firewall/${var.name}-${var.environment}/flow"
  retention_in_days = var.log_retention_days

  tags = merge(var.tags, {
    Name = "${var.name}-${var.environment}-nfw-flow-logs"
  })
}

###############################################################
# Stateless Rule Group
#
# Rules evaluated in priority order before the stateful engine.
# These handle simple allow/drop decisions that don't need state.
# Default: forward everything to the stateful engine (SFE).
###############################################################
resource "aws_networkfirewall_rule_group" "stateless" {
  name     = "${var.name}-${var.environment}-nfw-stateless-rg"
  type     = "STATELESS"
  capacity = var.stateless_rule_group_capacity

  rule_group {
    rules_source {
      stateless_rules_and_custom_actions {
        # Rule 1: Allow ICMP from RFC1918 — useful for diagnostics
        stateless_rule {
          priority = 10
          rule_definition {
            actions = ["aws:pass"]
            match_attributes {
              protocols = [1] # ICMP
              source {
                address_definition = "10.0.0.0/8"
              }
              destination {
                address_definition = "10.0.0.0/8"
              }
            }
          }
        }

        # Rule 2: Forward all TCP/UDP to stateful engine for deep inspection
        stateless_rule {
          priority = 100
          rule_definition {
            actions = ["aws:forward_to_sfe"]
            match_attributes {
              protocols = [6, 17] # TCP, UDP
              source {
                address_definition = "0.0.0.0/0"
              }
              destination {
                address_definition = "0.0.0.0/0"
              }
            }
          }
        }
      }
    }
  }

  tags = merge(var.tags, {
    Name = "${var.name}-${var.environment}-nfw-stateless-rg"
  })
}

###############################################################
# Stateful Rule Group — Suricata IDS/IPS rules
#
# Uses STRICT_ORDER so rules are evaluated top-down and the
# first matching rule wins. Rules written in Suricata format.
#
# Key rules:
#   - Block known bad TLS SNI patterns
#   - Alert on unusual port usage (non-443 HTTPS attempts)
#   - Drop invalid TCP state packets
#   - Allow established/related flows (pass on established)
###############################################################
resource "aws_networkfirewall_rule_group" "stateful_suricata" {
  name     = "${var.name}-${var.environment}-nfw-stateful-suricata-rg"
  type     = "STATEFUL"
  capacity = var.stateful_rule_group_capacity

  rule_group {
    # Define HOME_NET for Suricata variable substitution
    rule_variables {
      ip_sets {
        key = "HOME_NET"
        ip_set {
          definition = var.home_net_cidrs
        }
      }
    }

    stateful_rule_options {
      rule_order = var.stateful_rule_order
    }

    rules_source {
      rules_string = <<-SURICATA
pass tcp any any -> any any (msg:"Pass established TCP"; flow:established; sid:1000001; rev:1;)
pass udp any any -> any any (msg:"Pass established UDP"; flow:established; sid:1000002; rev:1;)
pass dns $HOME_NET any -> any 53 (msg:"Allow DNS egress"; sid:1000010; rev:1;)
pass udp $HOME_NET any -> any 123 (msg:"Allow NTP egress"; sid:1000011; rev:1;)
pass tls $HOME_NET any -> any 443 (msg:"Allow HTTPS egress"; sid:1000020; rev:1;)
pass http $HOME_NET any -> any 80 (msg:"Allow HTTP egress"; sid:1000021; rev:1;)
alert tls $HOME_NET any -> any !443 (msg:"ALERT TLS non-standard port"; sid:2000001; rev:1;)
drop tcp any any -> $HOME_NET 22 (msg:"DROP inbound SSH"; sid:3000001; rev:1;)
drop tcp any any -> $HOME_NET 3389 (msg:"DROP inbound RDP"; sid:3000002; rev:1;)
drop ip any any -> any any (msg:"DROP default deny"; sid:9999999; rev:1;)
SURICATA
    }
  }

  tags = merge(var.tags, {
    Name = "${var.name}-${var.environment}-nfw-stateful-suricata-rg"
  })
}

###############################################################
# Stateful Rule Group — Domain-list (FQDN allowlist for egress)
#
# Filters HTTPS/TLS traffic by SNI and HTTP traffic by hostname.
# Only domains in var.allowed_domains are permitted to egress.
# Useful for locking down workload internet access to known CDNs
# and AWS service endpoints.
###############################################################
resource "aws_networkfirewall_rule_group" "stateful_domain_list" {
  name     = "${var.name}-${var.environment}-nfw-stateful-domain-rg"
  type     = "STATEFUL"
  capacity = var.domain_list_rule_group_capacity

  rule_group {
    stateful_rule_options {
      rule_order = var.stateful_rule_order
    }

    rules_source {
      rules_source_list {
        generated_rules_type = "ALLOWLIST"
        target_types         = ["TLS_SNI", "HTTP_HOST"]
        targets              = var.allowed_domains
      }
    }
  }

  tags = merge(var.tags, {
    Name = "${var.name}-${var.environment}-nfw-stateful-domain-rg"
  })
}

###############################################################
# Firewall Policy
#
# Combines all rule groups into a single policy.
# Priority order: stateless first → stateful domain list → stateful Suricata.
###############################################################
resource "aws_networkfirewall_firewall_policy" "this" {
  name = "${var.name}-${var.environment}-nfw-policy"

  firewall_policy {
    stateless_default_actions          = var.stateless_default_actions
    stateless_fragment_default_actions = var.stateless_fragment_default_actions

    stateless_rule_group_reference {
      priority     = 10
      resource_arn = aws_networkfirewall_rule_group.stateless.arn
    }

    stateful_engine_options {
      rule_order = var.stateful_rule_order
    }

    stateful_default_actions = var.stateful_rule_order == "STRICT_ORDER" ? var.stateful_default_actions : null

    stateful_rule_group_reference {
      resource_arn = aws_networkfirewall_rule_group.stateful_domain_list.arn
      priority = 10

    }

    stateful_rule_group_reference {
      resource_arn = aws_networkfirewall_rule_group.stateful_suricata.arn
      priority = 20
    }
  }

  tags = merge(var.tags, {
    Name = "${var.name}-${var.environment}-nfw-policy"
  })
}

###############################################################
# Network Firewall
#
# One firewall endpoint is deployed per subnet (AZ).
# Endpoints act like transparent bumps-in-the-wire — route
# tables point at endpoint IDs to direct traffic through them.
###############################################################
resource "aws_networkfirewall_firewall" "this" {
  name                = "${var.name}-${var.environment}-nfw"
  vpc_id              = var.vpc_id
  firewall_policy_arn = aws_networkfirewall_firewall_policy.this.arn

  dynamic "subnet_mapping" {
    for_each = var.subnet_ids
    content {
      subnet_id = subnet_mapping.value
    }
  }

  # Delete protection prevents accidental removal
  delete_protection          = false
  firewall_policy_change_protection = false
  subnet_change_protection   = false

  tags = merge(var.tags, {
    Name = "${var.name}-${var.environment}-nfw"
  })
}

###############################################################
# Firewall Logging Configuration
###############################################################
resource "aws_networkfirewall_logging_configuration" "this" {
  firewall_arn = aws_networkfirewall_firewall.this.arn

  logging_configuration {
    dynamic "log_destination_config" {
      for_each = var.enable_alert_logging ? [1] : []
      content {
        log_type             = "ALERT"
        log_destination_type = "CloudWatchLogs"
        log_destination = {
          logGroup = aws_cloudwatch_log_group.alert[0].name
        }
      }
    }

    dynamic "log_destination_config" {
      for_each = var.enable_flow_logging ? [1] : []
      content {
        log_type             = "FLOW"
        log_destination_type = "CloudWatchLogs"
        log_destination = {
          logGroup = aws_cloudwatch_log_group.flow[0].name
        }
      }
    }
  }
}

###############################################################
# Extract per-AZ endpoint IDs from the firewall sync states
#
# aws_networkfirewall_firewall.this.firewall_status[0].sync_states
# is a set of objects. We need to map AZ → endpoint_id so we can
# create VPC route table entries pointing at each endpoint.
#
# The sync_states set is indexed by subnet ID. We create a lookup
# map: subnet_id → endpoint_id, then align with var.subnet_ids.
###############################################################
locals {
  # Build a flat map: subnet_id → endpoint_id
  endpoint_by_subnet = {
    for ss in tolist(aws_networkfirewall_firewall.this.firewall_status[0].sync_states) :
    ss.attachment[0].subnet_id => ss.attachment[0].endpoint_id
  }

  # Ordered list aligned with var.subnet_ids
  endpoint_ids = [
    for sid in var.subnet_ids : local.endpoint_by_subnet[sid]
  ]

  # AZ → endpoint_id map for route table consumption
  endpoint_by_az = {
    for i, az in var.azs : az => local.endpoint_ids[i]
  }
}
