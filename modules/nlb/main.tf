###############################################################
# Module: nlb
# Internet-facing Network Load Balancer
#
# Traffic flow:
#   Internet → NLB (this) → ALB (internal) → Spoke workloads via TGW
#
# The NLB sits in the ingress VPC's NLB subnets (/27 per AZ).
# It terminates TCP and forwards to the internal ALB using an
# ALB ARN target (IP target group pointing at the ALB's fixed IPs
# is not needed — we use an ALB target type "alb" introduced in
# the aws_lb_target_group alb target type).
#
# If certificate_arn is provided, TLS is terminated at the NLB
# (TLS listener → TCP to ALB). If empty, TCP passthrough is used
# (ALB handles TLS termination end-to-end).
###############################################################

###############################################################
# NLB — Internet-facing
###############################################################
resource "aws_lb" "this" {
  name                             = "${var.name}-${var.environment}-nlb"
  load_balancer_type               = "network"
  internal                         = false
  subnets                          = var.subnet_ids
  security_groups                  = [var.security_group_id]
  enable_cross_zone_load_balancing = var.enable_cross_zone_load_balancing
  enable_deletion_protection       = var.enable_deletion_protection

  dynamic "access_logs" {
    for_each = var.access_logs_bucket != "" ? [1] : []
    content {
      bucket  = var.access_logs_bucket
      prefix  = var.access_logs_prefix
      enabled = true
    }
  }

  tags = merge(var.tags, {
    Name = "${var.name}-${var.environment}-nlb"
    Tier = "ingress-nlb"
  })
}

###############################################################
# Target Group — ALB as target (target_type = "alb")
#
# This allows the NLB to forward directly to the ALB without
# managing individual IP targets. AWS manages the ALB IPs.
# Protocol must be TCP or TLS when target_type = "alb".
###############################################################
resource "aws_lb_target_group" "alb" {
  name        = "${var.name}-${var.environment}-nlb-alb-tg"
  port        = var.alb_target_port
  protocol    = "TCP"
  target_type = "alb"
  vpc_id      = var.vpc_id

  health_check {
    enabled             = true
    protocol            = var.health_check_protocol
    port                = var.health_check_port
    interval            = var.health_check_interval
    healthy_threshold   = var.health_check_healthy_threshold
    unhealthy_threshold = var.health_check_unhealthy_threshold
  }

  tags = merge(var.tags, {
    Name = "${var.name}-${var.environment}-nlb-alb-tg"
  })
}

###############################################################
# Register ALB as target in the NLB target group
###############################################################
resource "aws_lb_target_group_attachment" "alb" {
  target_group_arn = aws_lb_target_group.alb.arn
  target_id        = var.alb_arn
  port             = var.alb_target_port
}

###############################################################
# Listener — HTTPS (443)
#
# If certificate_arn is set: TLS listener, NLB terminates TLS,
#   forwards as TCP to ALB on alb_target_port (443).
# If empty: TCP passthrough on port 443, forwards to ALB.
#   Only created when alb_target_port = 443 (ALB has HTTPS).
#   When alb_target_port = 80, skip this listener to avoid the
#   "no matching listener" error on the ALB target.
###############################################################
resource "aws_lb_listener" "https" {
  count             = var.alb_target_port == 443 ? 1 : 0
  load_balancer_arn = aws_lb.this.arn
  port              = var.https_port
  protocol          = var.certificate_arn != "" ? "TLS" : "TCP"
  certificate_arn   = var.certificate_arn != "" ? var.certificate_arn : null
  ssl_policy        = var.certificate_arn != "" ? "ELBSecurityPolicy-TLS13-1-2-2021-06" : null

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.alb.arn
  }

  tags = merge(var.tags, {
    Name = "${var.name}-${var.environment}-nlb-listener-https"
  })
}

###############################################################
# Listener — HTTP (80)
#
# Always created. Forwards TCP/80 to the ALB.
# When alb_target_port = 80 (no HTTPS cert), this is the only
# active listener and handles all traffic.
# When alb_target_port = 443, this forwards HTTP to the ALB
# which redirects it to HTTPS.
###############################################################
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = var.http_port
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.alb.arn
  }

  tags = merge(var.tags, {
    Name = "${var.name}-${var.environment}-nlb-listener-http"
  })
}
