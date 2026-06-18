###############################################################
# Module: network_firewall (egress)
# AWS Network Firewall — Inspect VPC
#
# Policy: DEFAULT_ACTION_ORDER (no default drop, pass-all)
# Custom Suricata rules from egress-suricata.rules file
###############################################################

data "aws_region" "current" {}

###############################################################
# CloudWatch Log Groups
###############################################################
resource "aws_cloudwatch_log_group" "alert" {
  count             = var.enable_alert_logging ? 1 : 0
  name              = "/aws/network-firewall/${var.name}-${var.environment}/alert"
  retention_in_days = var.log_retention_days
  tags = merge(var.tags, { Name = "${var.name}-${var.environment}-nfw-alert-logs" })
}

resource "aws_cloudwatch_log_group" "flow" {
  count             = var.enable_flow_logging ? 1 : 0
  name              = "/aws/network-firewall/${var.name}-${var.environment}/flow"
  retention_in_days = var.log_retention_days
  tags = merge(var.tags, { Name = "${var.name}-${var.environment}-nfw-flow-logs" })
}

###############################################################
# Custom Suricata Rule Group
###############################################################
resource "aws_networkfirewall_rule_group" "egress_suricata" {
  capacity = var.stateful_rule_group_capacity
  name     = "${var.name}-${var.environment}-egress-suricata-rules"
  type     = "STATEFUL"

  rule_group {
    rule_variables {
      ip_sets {
        key = "HOME_NET"
        ip_set { definition = var.home_net_cidrs }
      }
    }

    rules_source {
      rules_string = file("${path.module}/egress-suricata.rules")
    }
  }

  tags = merge(var.tags, { Name = "${var.name}-${var.environment}-egress-suricata-rules" })
}

###############################################################
# Firewall Policy — DEFAULT_ACTION_ORDER
###############################################################
resource "aws_networkfirewall_firewall_policy" "this" {
  name = "${var.name}-${var.environment}-nfw-policy"

  firewall_policy {
    stateless_default_actions          = ["aws:forward_to_sfe"]
    stateless_fragment_default_actions = ["aws:forward_to_sfe"]

    stateful_engine_options {
      rule_order = "DEFAULT_ACTION_ORDER"
    }

    stateful_rule_group_reference {
      resource_arn = aws_networkfirewall_rule_group.egress_suricata.arn
    }
  }

  tags = merge(var.tags, { Name = "${var.name}-${var.environment}-nfw-policy" })
}

###############################################################
# Network Firewall
###############################################################
resource "aws_networkfirewall_firewall" "this" {
  name                = "${var.name}-${var.environment}-nfw"
  vpc_id              = var.vpc_id
  firewall_policy_arn = aws_networkfirewall_firewall_policy.this.arn

  dynamic "subnet_mapping" {
    for_each = var.subnet_ids
    content { subnet_id = subnet_mapping.value }
  }

  delete_protection                 = false
  firewall_policy_change_protection = false
  subnet_change_protection          = false

  tags = merge(var.tags, { Name = "${var.name}-${var.environment}-nfw" })
}

###############################################################
# Logging
###############################################################
resource "aws_networkfirewall_logging_configuration" "this" {
  firewall_arn = aws_networkfirewall_firewall.this.arn

  logging_configuration {
    dynamic "log_destination_config" {
      for_each = var.enable_alert_logging ? [1] : []
      content {
        log_type             = "ALERT"
        log_destination_type = "CloudWatchLogs"
        log_destination      = { logGroup = aws_cloudwatch_log_group.alert[0].name }
      }
    }
    dynamic "log_destination_config" {
      for_each = var.enable_flow_logging ? [1] : []
      content {
        log_type             = "FLOW"
        log_destination_type = "CloudWatchLogs"
        log_destination      = { logGroup = aws_cloudwatch_log_group.flow[0].name }
      }
    }
  }
}

###############################################################
# Endpoint IDs
###############################################################
locals {
  endpoint_by_subnet = {
    for ss in tolist(aws_networkfirewall_firewall.this.firewall_status[0].sync_states) :
    ss.attachment[0].subnet_id => ss.attachment[0].endpoint_id
  }
  endpoint_ids = [for sid in var.subnet_ids : local.endpoint_by_subnet[sid]]
  endpoint_by_az = { for i, az in var.azs : az => local.endpoint_ids[i] }
}
