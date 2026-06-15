###############################################################
# Module: alb
# Internal Application Load Balancer
#
# Traffic flow:
#   NLB → ALB (this, internal) → target groups → spoke workloads
#
# The ALB is internal (no public IPs). It sits in the ALB subnets
# of the ingress VPC. Routing to spoke workloads is done via the
# ALB subnet route table which forwards spoke CIDRs → TGW.
#
# Listener configuration:
#   Port 80  → 301 redirect to HTTPS (or forward, configurable)
#   Port 443 → HTTPS, routes to target groups via listener rules
#              Default action returns 404 Fixed Response when no
#              rule matches.
#
# Listener rules support host-header and path-pattern conditions.
# Each rule gets its own target group so workload teams can
# register their own targets independently.
###############################################################

###############################################################
# ALB — Internal
###############################################################
resource "aws_lb" "this" {
  name                       = "${var.name}-${var.environment}-alb"
  load_balancer_type         = "application"
  internal                   = true
  subnets                    = var.subnet_ids
  security_groups            = [var.security_group_id]
  enable_deletion_protection = var.enable_deletion_protection
  enable_http2               = var.enable_http2
  idle_timeout               = var.idle_timeout

  dynamic "access_logs" {
    for_each = var.access_logs_bucket != "" ? [1] : []
    content {
      bucket  = var.access_logs_bucket
      prefix  = var.access_logs_prefix
      enabled = true
    }
  }

  tags = merge(var.tags, {
    Name = "${var.name}-${var.environment}-alb"
    Tier = "ingress-alb"
  })
}

###############################################################
# Default target group — catch-all for unmatched requests
#
# This TG is attached to the default action of the HTTPS listener.
# In production you'd register a maintenance-page backend here.
# For now it returns 503 via a fixed-response default action so
# the TG itself can remain empty without causing health failures.
###############################################################
resource "aws_lb_target_group" "default" {
  name                 = "${var.name}-${var.environment}-alb-default-tg"
  port                 = var.default_target_group_port
  protocol             = var.default_target_group_protocol
  target_type          = var.default_target_group_type
  vpc_id               = var.vpc_id
  deregistration_delay = 30

  health_check {
    enabled             = true
    path                = var.default_health_check_path
    protocol            = var.default_health_check_protocol
    matcher             = var.default_health_check_matcher
    interval            = var.default_health_check_interval
    timeout             = var.default_health_check_timeout
    healthy_threshold   = var.default_health_check_healthy_threshold
    unhealthy_threshold = var.default_health_check_unhealthy_threshold
  }

  tags = merge(var.tags, {
    Name = "${var.name}-${var.environment}-alb-default-tg"
  })
}

###############################################################
# Listener — HTTP/80
#
# When http_redirect_to_https = true AND HTTPS listener exists → 301 redirect.
# Otherwise → forward to default TG (used when no cert is present).
###############################################################
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = var.http_redirect_to_https && var.enable_https ? "redirect" : "forward"

    dynamic "redirect" {
      for_each = var.http_redirect_to_https && var.enable_https ? [1] : []
      content {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }

    target_group_arn = var.http_redirect_to_https && var.enable_https ? null : aws_lb_target_group.default.arn
  }

  tags = merge(var.tags, {
    Name = "${var.name}-${var.environment}-alb-listener-http"
  })
}

###############################################################
# Listener — HTTPS/443
#
# Default action: fixed 503 response (no matched rule).
# Actual workload routing is done via listener rules below.
# If enable_https = false this resource is not created.
###############################################################
resource "aws_lb_listener" "https" {
  count             = var.enable_https ? 1 : 0
  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = var.ssl_policy
  certificate_arn   = var.certificate_arn

  # Default: return 503 for unmatched requests
  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "503 - No matching service"
      status_code  = "503"
    }
  }

  tags = merge(var.tags, {
    Name = "${var.name}-${var.environment}-alb-listener-https"
  })

  lifecycle {
    precondition {
      condition     = var.certificate_arn != ""
      error_message = "certificate_arn must be set when enable_https = true."
    }
  }
}

###############################################################
# Per-rule target groups
#
# One target group per listener rule entry in var.listener_rules.
# Named using the rule's target_group.name field so workload
# teams can identify their own TG in the console.
###############################################################
resource "aws_lb_target_group" "rules" {
  for_each = { for r in var.listener_rules : r.target_group.name => r.target_group }

  name                 = "${var.name}-${var.environment}-${each.key}-tg"
  port                 = each.value.port
  protocol             = each.value.protocol
  target_type          = each.value.target_type
  vpc_id               = var.vpc_id
  deregistration_delay = each.value.deregistration_delay

  dynamic "stickiness" {
    for_each = each.value.stickiness_enabled ? [1] : []
    content {
      type            = "lb_cookie"
      enabled         = true
      cookie_duration = 86400
    }
  }

  health_check {
    enabled             = true
    path                = each.value.health_check_path
    protocol            = each.value.health_check_protocol
    matcher             = each.value.health_check_matcher
    interval            = each.value.health_check_interval
    timeout             = each.value.health_check_timeout
    healthy_threshold   = each.value.healthy_threshold
    unhealthy_threshold = each.value.unhealthy_threshold
  }

  tags = merge(var.tags, {
    Name = "${var.name}-${var.environment}-${each.key}-tg"
  })
}

###############################################################
# Per-rule target group IP registrations
#
# Flattens the target_ips list from each listener rule into
# individual aws_lb_target_group_attachment resources so EC2
# private IPs can be registered directly from tfvars.
# Each attachment key is "<tg_name>/<ip>" for uniqueness.
###############################################################
locals {
  target_registrations = flatten([
    for r in var.listener_rules : [
      for ip in r.target_ips : {
        key  = "${r.target_group.name}/${ip}"
        name = r.target_group.name
        ip   = ip
        port = r.target_group.port
      }
    ]
  ])
}

resource "aws_lb_target_group_attachment" "rule_targets" {
  for_each = { for t in local.target_registrations : t.key => t }

  target_group_arn  = aws_lb_target_group.rules[each.value.name].arn
  target_id         = each.value.ip
  port              = each.value.port
  availability_zone = "all" # required for IP targets outside the ALB's VPC (cross-VPC via TGW)
}
# When HTTPS listener exists, rules attach to it.
# When only HTTP listener exists (no cert), rules attach to HTTP.
###############################################################
resource "aws_lb_listener_rule" "rules" {
  for_each = var.enable_https ? { for r in var.listener_rules : r.target_group.name => r } : {}

  listener_arn = aws_lb_listener.https[0].arn
  priority     = each.value.priority

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.rules[each.key].arn
  }

  dynamic "condition" {
    for_each = length(each.value.host_header) > 0 ? [each.value.host_header] : []
    content {
      host_header {
        values = condition.value
      }
    }
  }

  dynamic "condition" {
    for_each = length(each.value.path_pattern) > 0 ? [each.value.path_pattern] : []
    content {
      path_pattern {
        values = condition.value
      }
    }
  }

  tags = merge(var.tags, {
    Name = "${var.name}-${var.environment}-alb-rule-${each.key}"
  })
}

# HTTP listener rules — used when no cert is present (enable_https = false)
resource "aws_lb_listener_rule" "http_rules" {
  for_each = !var.enable_https ? { for r in var.listener_rules : r.target_group.name => r } : {}

  listener_arn = aws_lb_listener.http.arn
  priority     = each.value.priority

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.rules[each.key].arn
  }

  dynamic "condition" {
    for_each = length(each.value.host_header) > 0 ? [each.value.host_header] : []
    content {
      host_header {
        values = condition.value
      }
    }
  }

  dynamic "condition" {
    for_each = length(each.value.path_pattern) > 0 ? [each.value.path_pattern] : []
    content {
      path_pattern {
        values = condition.value
      }
    }
  }

  tags = merge(var.tags, {
    Name = "${var.name}-${var.environment}-alb-http-rule-${each.key}"
  })
}
