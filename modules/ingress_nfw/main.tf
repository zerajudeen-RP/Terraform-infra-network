###############################################################
# Module: ingress_nfw
# AWS Network Firewall — Ingress VPC
#
# Policy: STRICT_ORDER
# Default actions: aws:alert_established + aws:drop_established
# AWS Managed rule groups (priorities 100-400)
# Custom Suricata rules (priority 600)
###############################################################

data "aws_region" "current" {}

###############################################################
# CloudWatch Log Groups
###############################################################
resource "aws_cloudwatch_log_group" "alert" {
  count             = var.enable_alert_logging ? 1 : 0
  name              = "/aws/network-firewall/${var.name}-${var.environment}-ingress/alert"
  retention_in_days = var.log_retention_days
  tags = merge(var.tags, { Name = "${var.name}-${var.environment}-ingress-nfw-alert-logs" })
}

resource "aws_cloudwatch_log_group" "flow" {
  count             = var.enable_flow_logging ? 1 : 0
  name              = "/aws/network-firewall/${var.name}-${var.environment}-ingress/flow"
  retention_in_days = var.log_retention_days
  tags = merge(var.tags, { Name = "${var.name}-${var.environment}-ingress-nfw-flow-logs" })
}

###############################################################
# AWS Managed Threat Rule Group ARNs
###############################################################
locals {
  managed_rule_groups = {
    abused_legit_botnet  = "arn:aws:network-firewall:${data.aws_region.current.name}:aws-managed:stateful-rulegroup/AbusedLegitBotNetCommandAndControlDomainsStrictOrder"
    abused_legit_malware = "arn:aws:network-firewall:${data.aws_region.current.name}:aws-managed:stateful-rulegroup/AbusedLegitMalwareDomainsStrictOrder"
    botnet_command       = "arn:aws:network-firewall:${data.aws_region.current.name}:aws-managed:stateful-rulegroup/BotNetCommandAndControlDomainsStrictOrder"
    malware_domains      = "arn:aws:network-firewall:${data.aws_region.current.name}:aws-managed:stateful-rulegroup/MalwareDomainsStrictOrder"
  }
}

###############################################################
# Custom Suricata Rule Group
###############################################################
resource "aws_networkfirewall_rule_group" "ingress_suricata" {
  capacity = var.stateful_rule_group_capacity
  name     = "${var.name}-${var.environment}-ingress-suricata-rules"
  type     = "STATEFUL"

  rule_group {
    stateful_rule_options {
      rule_order = "STRICT_ORDER"
    }

    rule_variables {
      ip_sets {
        key = "NLB_PUBLIC_IPS"
        ip_set { definition = var.nlb_public_ips }
      }
      ip_sets {
        key = "NLB_PRIVATE_IPS"
        ip_set { definition = var.nlb_private_cidrs }
      }
      ip_sets {
        key = "ALB_PRIVATE_IPS"
        ip_set { definition = var.alb_private_cidrs }
      }
      port_sets {
        key = "HTTP_PORTS"
        port_set { definition = ["443", "80", "8443", "4443"] }
      }
    }

    rules_source {
      rules_string = templatefile("${path.module}/ingress-suricata.rules.tftpl", {
        geo_countries = "!AU,!US,!CA,!PR,!IN"
      })
    }
  }

  tags = merge(var.tags, { Name = "${var.name}-${var.environment}-ingress-suricata-rules" })
}

###############################################################
# Firewall Policy
###############################################################
resource "aws_networkfirewall_firewall_policy" "this" {
  name = "${var.name}-${var.environment}-ingress-nfw-policy"

  firewall_policy {
    stateless_default_actions          = ["aws:forward_to_sfe"]
    stateless_fragment_default_actions = ["aws:forward_to_sfe"]
    stateful_default_actions           = ["aws:alert_established", "aws:drop_established"]

    stateful_engine_options {
      rule_order = "STRICT_ORDER"
    }

    stateful_rule_group_reference {
      resource_arn = local.managed_rule_groups["abused_legit_botnet"]
      priority     = 100
    }
    stateful_rule_group_reference {
      resource_arn = local.managed_rule_groups["abused_legit_malware"]
      priority     = 200
    }
    stateful_rule_group_reference {
      resource_arn = local.managed_rule_groups["botnet_command"]
      priority     = 300
    }
    stateful_rule_group_reference {
      resource_arn = local.managed_rule_groups["malware_domains"]
      priority     = 400
    }
    stateful_rule_group_reference {
      resource_arn = aws_networkfirewall_rule_group.ingress_suricata.arn
      priority     = 600
    }
  }

  tags = merge(var.tags, { Name = "${var.name}-${var.environment}-ingress-nfw-policy" })
}

###############################################################
# Network Firewall
###############################################################
resource "aws_networkfirewall_firewall" "this" {
  name                = "${var.name}-${var.environment}-ingress-nfw"
  vpc_id              = var.vpc_id
  firewall_policy_arn = aws_networkfirewall_firewall_policy.this.arn

  dynamic "subnet_mapping" {
    for_each = var.subnet_ids
    content { subnet_id = subnet_mapping.value }
  }

  delete_protection                 = false
  firewall_policy_change_protection = false
  subnet_change_protection          = false

  tags = merge(var.tags, { Name = "${var.name}-${var.environment}-ingress-nfw" })
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
}
