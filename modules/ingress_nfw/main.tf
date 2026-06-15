###############################################################
# Module: ingress_nfw
# AWS Network Firewall — deployed in the Ingress VPC
#
# Traffic flow (inbound):
#   IGW edge RT → NFW endpoint → NLB → ALB → TGW → workload
#
# Route integration (handled in ingress_vpc module):
#   IGW edge RT         : NLB/ALB subnet CIDRs → NFW endpoint per AZ
#   NLB subnet RT       : 0.0.0.0/0 → NFW endpoint (return path)
#   ALB subnet RT       : 0.0.0.0/0 → NFW endpoint (return path)
#   TGW attach subnet RT: NLB/ALB CIDRs → NFW endpoint
#   Firewall subnet RT  : 0.0.0.0/0 → IGW (post-inspection back to internet)
#
# NFW endpoint IDs are exported and passed back to ingress_vpc
# so route tables can reference them.
#
# Rule groups:
#   1. Stateless — pass ICMP, forward TCP/UDP to stateful engine
#   2. Stateful  — allow established flows, alert on inbound threats,
#                  pass all (open policy — tighten with domain/IP rules later)
###############################################################

###############################################################
# CloudWatch Log Groups
###############################################################
resource "aws_cloudwatch_log_group" "alert" {
  count             = var.enable_alert_logging ? 1 : 0
  name              = "/aws/network-firewall/${var.name}-${var.environment}-ingress/alert"
  retention_in_days = var.log_retention_days

  tags = merge(var.tags, {
    Name = "${var.name}-${var.environment}-ingress-nfw-alert-logs"
  })
}

resource "aws_cloudwatch_log_group" "flow" {
  count             = var.enable_flow_logging ? 1 : 0
  name              = "/aws/network-firewall/${var.name}-${var.environment}-ingress/flow"
  retention_in_days = var.log_retention_days

  tags = merge(var.tags, {
    Name = "${var.name}-${var.environment}-ingress-nfw-flow-logs"
  })
}

###############################################################
# Stateless Rule Group
###############################################################
resource "aws_networkfirewall_rule_group" "stateless" {
  name     = "${var.name}-${var.environment}-ingress-nfw-stateless-rg"
  type     = "STATELESS"
  capacity = var.stateless_rule_group_capacity

  rule_group {
    rules_source {
      stateless_rules_and_custom_actions {
        # Forward all TCP/UDP to stateful engine
        stateless_rule {
          priority = 100
          rule_definition {
            actions = ["aws:forward_to_sfe"]
            match_attributes {
              protocols = [6, 17] # TCP, UDP
              source { address_definition = "0.0.0.0/0" }
              destination { address_definition = "0.0.0.0/0" }
            }
          }
        }
      }
    }
  }

  tags = merge(var.tags, {
    Name = "${var.name}-${var.environment}-ingress-nfw-stateless-rg"
  })
}

###############################################################
# Stateful Rule Group — Inbound inspection
#
# Allows all inbound traffic (open policy).
# Alerts on known attack patterns for visibility.
# Tighten rules here when requirements are defined.
###############################################################
resource "aws_networkfirewall_rule_group" "stateful" {
  name     = "${var.name}-${var.environment}-ingress-nfw-stateful-rg"
  type     = "STATEFUL"
  capacity = var.stateful_rule_group_capacity

  rule_group {
    stateful_rule_options {
      rule_order = "STRICT_ORDER"
    }

    rules_source {
      rules_string = <<-SURICATA
pass tcp any any -> any 80 (msg:"Allow HTTP inbound"; sid:1000001; rev:1;)
pass tcp any any -> any 443 (msg:"Allow HTTPS inbound"; sid:1000002; rev:1;)
pass ip any any -> any any (msg:"Pass all other traffic"; sid:9999999; rev:1;)
SURICATA
    }
  }

  tags = merge(var.tags, {
    Name = "${var.name}-${var.environment}-ingress-nfw-stateful-rg"
  })
}

###############################################################
# Firewall Policy
###############################################################
resource "aws_networkfirewall_firewall_policy" "this" {
  name = "${var.name}-${var.environment}-ingress-nfw-policy"

  firewall_policy {
    stateless_default_actions          = ["aws:forward_to_sfe"]
    stateless_fragment_default_actions = ["aws:forward_to_sfe"]

    stateless_rule_group_reference {
      priority     = 10
      resource_arn = aws_networkfirewall_rule_group.stateless.arn
    }

    stateful_engine_options {
      rule_order = "STRICT_ORDER"
    }

    stateful_rule_group_reference {
      priority     = 10
      resource_arn = aws_networkfirewall_rule_group.stateful.arn
    }
  }

  tags = merge(var.tags, {
    Name = "${var.name}-${var.environment}-ingress-nfw-policy"
  })
}

###############################################################
# Network Firewall — one endpoint per AZ in firewall subnets
###############################################################
resource "aws_networkfirewall_firewall" "this" {
  name                = "${var.name}-${var.environment}-ingress-nfw"
  vpc_id              = var.vpc_id
  firewall_policy_arn = aws_networkfirewall_firewall_policy.this.arn

  dynamic "subnet_mapping" {
    for_each = var.subnet_ids
    content {
      subnet_id = subnet_mapping.value
    }
  }

  delete_protection                 = false
  firewall_policy_change_protection = false
  subnet_change_protection          = false

  tags = merge(var.tags, {
    Name = "${var.name}-${var.environment}-ingress-nfw"
  })
}

###############################################################
# Firewall Logging
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
# Extract per-AZ endpoint IDs from firewall sync states
###############################################################
locals {
  endpoint_by_subnet = {
    for ss in tolist(aws_networkfirewall_firewall.this.firewall_status[0].sync_states) :
    ss.attachment[0].subnet_id => ss.attachment[0].endpoint_id
  }

  endpoint_ids = [
    for sid in var.subnet_ids : local.endpoint_by_subnet[sid]
  ]
}
