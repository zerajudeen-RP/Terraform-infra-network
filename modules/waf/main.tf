###############################################################
# Module: waf
# AWS WAF v2 WebACL — attached to the internal ALB
#
# Managed rule groups included:
#   1. AWSManagedRulesCommonRuleSet       — OWASP Top 10 core rules
#   2. AWSManagedRulesKnownBadInputsRuleSet — known bad inputs (Log4j, etc.)
#   3. AWSManagedRulesAmazonIpReputationList — AWS threat intel IP blocklist
#   4. AWSManagedRulesSQLiRuleSet          — SQL injection protection
#
# Rate limiting:
#   - 2000 requests per 5 minutes per source IP (configurable)
#
# Logging:
#   - CloudWatch Logs (optional, enabled by default)
#
# Scope must be REGIONAL for ALB (CLOUDFRONT only for CloudFront).
###############################################################

###############################################################
# CloudWatch Log Group for WAF
###############################################################
resource "aws_cloudwatch_log_group" "waf" {
  count = var.enable_logging ? 1 : 0

  # WAF log group name MUST start with "aws-waf-logs-"
  name              = "aws-waf-logs-${var.name}-${var.environment}-alb"
  retention_in_days = var.log_retention_days

  tags = merge(var.tags, {
    Name = "${var.name}-${var.environment}-waf-logs"
  })
}

###############################################################
# WAF WebACL
###############################################################
resource "aws_wafv2_web_acl" "this" {
  name        = "${var.name}-${var.environment}-waf"
  description = "WAF WebACL for ${var.name}-${var.environment} ALB"
  scope       = "REGIONAL"

  default_action {
    allow {}
  }

  ###############################################################
  # Rule 1 — AWS IP Reputation List (priority 10)
  # Blocks IPs on AWS threat intelligence lists (botnets, scanners)
  ###############################################################
  rule {
    name     = "AWSManagedRulesAmazonIpReputationList"
    priority = 10

    override_action {
      none {} # use the rule group's own actions (block)
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesAmazonIpReputationList"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.name}-${var.environment}-ip-reputation"
      sampled_requests_enabled   = true
    }
  }

  ###############################################################
  # Rule 2 — Known Bad Inputs (priority 20)
  # Blocks requests with patterns known to be malicious
  # (Log4JRCE, SSRF attempts, etc.)
  ###############################################################
  rule {
    name     = "AWSManagedRulesKnownBadInputsRuleSet"
    priority = 20

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.name}-${var.environment}-known-bad-inputs"
      sampled_requests_enabled   = true
    }
  }

  ###############################################################
  # Rule 3 — Core Rule Set / OWASP Top 10 (priority 30)
  ###############################################################
  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 30

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.name}-${var.environment}-common-rules"
      sampled_requests_enabled   = true
    }
  }

  ###############################################################
  # Rule 4 — SQL Injection (priority 40)
  ###############################################################
  rule {
    name     = "AWSManagedRulesSQLiRuleSet"
    priority = 40

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesSQLiRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.name}-${var.environment}-sqli"
      sampled_requests_enabled   = true
    }
  }

  ###############################################################
  # Rule 5 — Rate limiting (priority 50)
  # Blocks IPs exceeding the request rate threshold
  ###############################################################
  rule {
    name     = "RateLimitRule"
    priority = 50

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = var.rate_limit
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.name}-${var.environment}-rate-limit"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.name}-${var.environment}-waf"
    sampled_requests_enabled   = true
  }

  tags = merge(var.tags, {
    Name = "${var.name}-${var.environment}-waf"
  })
}

###############################################################
# Associate WebACL with the ALB
###############################################################
resource "aws_wafv2_web_acl_association" "alb" {
  resource_arn = var.alb_arn
  web_acl_arn  = aws_wafv2_web_acl.this.arn
}

###############################################################
# WAF Logging Configuration
###############################################################
resource "aws_wafv2_web_acl_logging_configuration" "this" {
  count = var.enable_logging ? 1 : 0

  log_destination_configs = [aws_cloudwatch_log_group.waf[0].arn]
  resource_arn            = aws_wafv2_web_acl.this.arn
}
