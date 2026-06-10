# =============================================================================
# ALB를 Terraform에서 직접 생성 (ALB Controller/Ingress 의존 제거)
#  - wsc-app-lb: internal, private subnets, /health→403, /v1/*→앱, 그외→404
#  - wsc-addon-lb: internet-facing, public subnets, /grafana→grafana, /prometheus→prometheus
# =============================================================================

# ---- 공통 SG (전체 오픈) ----
resource "aws_security_group" "alb" {
  name        = "wsc-alb-sg"
  description = "ALB SG - all open"
  vpc_id      = local.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "wsc-alb-sg" }
}

# ============ wsc-app-lb (internal) ============
resource "aws_lb" "app" {
  name               = "wsc-app-lb"
  internal           = true
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = [local.subnet_ids["wsc-private-a"], local.subnet_ids["wsc-private-c"]]

  tags = { Name = "wsc-app-lb" }
}

resource "aws_lb_target_group" "app" {
  name        = "wsc-app-tg"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = local.vpc_id
  target_type = "ip"

  health_check {
    path                = "/health"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = { Name = "wsc-app-tg" }
}

resource "aws_lb_listener" "app" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "Contents Not Found"
      status_code  = "404"
    }
  }
}

resource "aws_lb_listener_rule" "app_health_deny" {
  listener_arn = aws_lb_listener.app.arn
  priority     = 1

  action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "Restrict access to api"
      status_code  = "403"
    }
  }

  condition {
    path_pattern { values = ["/health", "/health/*"] }
  }
}

resource "aws_lb_listener_rule" "app_api" {
  listener_arn = aws_lb_listener.app.arn
  priority     = 2

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }

  condition {
    path_pattern { values = ["/v1/*"] }
  }
}

# ============ wsc-addon-lb (internet-facing) ============
resource "aws_lb" "addon" {
  name               = "wsc-addon-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = [local.subnet_ids["wsc-public-a"], local.subnet_ids["wsc-public-c"]]

  tags = { Name = "wsc-addon-lb" }
}

resource "aws_lb_target_group" "prometheus" {
  name        = "wsc-prometheus-tg"
  port        = 9090
  protocol    = "HTTP"
  vpc_id      = local.vpc_id
  target_type = "ip"

  health_check {
    path    = "/prometheus/-/healthy"
    matcher = "200"
  }

  tags = { Name = "wsc-prometheus-tg" }
}

resource "aws_lb_target_group" "grafana" {
  name        = "wsc-grafana-tg"
  port        = 3000
  protocol    = "HTTP"
  vpc_id      = local.vpc_id
  target_type = "ip"

  health_check {
    path    = "/grafana/api/health"
    matcher = "200"
  }

  tags = { Name = "wsc-grafana-tg" }
}

resource "aws_lb_listener" "addon" {
  load_balancer_arn = aws_lb.addon.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "Not Found"
      status_code  = "404"
    }
  }
}

resource "aws_lb_listener_rule" "addon_prometheus" {
  listener_arn = aws_lb_listener.addon.arn
  priority     = 1

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.prometheus.arn
  }

  condition {
    path_pattern { values = ["/prometheus", "/prometheus/*"] }
  }
}

resource "aws_lb_listener_rule" "addon_grafana" {
  listener_arn = aws_lb_listener.addon.arn
  priority     = 2

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.grafana.arn
  }

  condition {
    path_pattern { values = ["/grafana", "/grafana/*"] }
  }
}

# ---- Outputs ----
output "app_alb_dns" {
  value = aws_lb.app.dns_name
}

output "addon_alb_dns" {
  value = aws_lb.addon.dns_name
}

output "app_tg_arn" {
  description = "App TG ARN - deploy-k8s.sh에서 TargetGroupBinding으로 Pod 등록에 사용"
  value       = aws_lb_target_group.app.arn
}

output "prometheus_tg_arn" {
  value = aws_lb_target_group.prometheus.arn
}

output "grafana_tg_arn" {
  value = aws_lb_target_group.grafana.arn
}
