# =============================================================================
# ALB (Terraform 직접 생성 — apply 한 번에 CloudFront 연결까지 완료)
# =============================================================================

resource "aws_security_group" "alb" {
  name   = "wsc-alb-sg"
  vpc_id = local.vpc_id
  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    prefix_list_ids = [data.aws_ec2_managed_prefix_list.cloudfront.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "wsc-alb-sg" }
}

# ALB → Pod 통신 허용 (EKS 클러스터 SG에 ALB SG 인바운드 추가)
resource "aws_security_group_rule" "alb_to_pods" {
  type                     = "ingress"
  description              = "ALB to Pod ports"
  from_port                = 0
  to_port                  = 65535
  protocol                 = "tcp"
  security_group_id        = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
  source_security_group_id = aws_security_group.alb.id
}

# ---- wsc-app-lb (internal, private subnets) ----
resource "aws_lb" "app" {
  name               = "wsc-app-lb"
  internal           = true
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = [local.subnet_ids["wsc-private-a"], local.subnet_ids["wsc-private-c"]]
  tags               = { Name = "wsc-app-lb" }
}

resource "aws_lb_target_group" "app" {
  name        = "wsc-app-tg"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = local.vpc_id
  target_type = "ip"
  health_check {
    path     = "/health"
    matcher  = "200"
    interval = 15
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

resource "aws_lb_listener_rule" "app_health" {
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

# ---- wsc-addon-lb (internet-facing, public subnets) ----
resource "aws_lb" "addon" {
  name               = "wsc-addon-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = [local.subnet_ids["wsc-public-a"], local.subnet_ids["wsc-public-c"]]
  tags               = { Name = "wsc-addon-lb" }
}

resource "aws_lb_target_group" "prometheus" {
  name        = "wsc-prometheus-tg"
  port        = 9090
  protocol    = "HTTP"
  vpc_id      = local.vpc_id
  target_type = "ip"
  health_check {
    path    = "/prometheus/-/healthy"
    matcher = "200,301,302"
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
    path    = "/api/health"
    matcher = "200,301,302"
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

output "app_tg_arn" {
  value = aws_lb_target_group.app.arn
}
output "prometheus_tg_arn" {
  value = aws_lb_target_group.prometheus.arn
}
output "grafana_tg_arn" {
  value = aws_lb_target_group.grafana.arn
}
