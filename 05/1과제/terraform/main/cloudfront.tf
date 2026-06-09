# =============================================================================
# WAF (wsc-waf) + CloudFront (wsc-cdn)
#  - WAF: CLOUDFRONT scope(us-east-1), POST Body에 admin/sysop 포함 시 Block
#  - CloudFront: S3(정적, 캐싱) + ALB(앱, 비캐싱/쿼리스트링 전달) Origin,
#                HTTP->HTTPS 리다이렉트, IPv6 비활성, 글로벌 엣지
# =============================================================================

# ---- WAF Web ACL ----
resource "aws_wafv2_web_acl" "waf" {
  provider = aws.use1
  name     = "wsc-waf"
  scope    = "CLOUDFRONT"

  default_action {
    allow {}
  }

  rule {
    name     = "block-admin"
    priority = 1
    action {
      block {}
    }
    statement {
      byte_match_statement {
        search_string         = "admin"
        positional_constraint = "CONTAINS"
        field_to_match {
          body {}
        }
        text_transformation {
          priority = 0
          type     = "LOWERCASE"
        }
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "block-admin"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "block-sysop"
    priority = 2
    action {
      block {}
    }
    statement {
      byte_match_statement {
        search_string         = "sysop"
        positional_constraint = "CONTAINS"
        field_to_match {
          body {}
        }
        text_transformation {
          priority = 0
          type     = "LOWERCASE"
        }
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "block-sysop"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "wsc-waf"
    sampled_requests_enabled   = true
  }

  tags = { Name = "wsc-waf" }
}

# ---- CloudFront OAC (S3) ----
resource "aws_cloudfront_origin_access_control" "s3" {
  name                              = "wsc-s3-oac-${random_id.oac.hex}"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

data "aws_cloudfront_cache_policy" "optimized" {
  name = "Managed-CachingOptimized"
}

data "aws_cloudfront_cache_policy" "disabled" {
  name = "Managed-CachingDisabled"
}

data "aws_cloudfront_origin_request_policy" "all_viewer" {
  name = "Managed-AllViewer"
}

locals {
  s3_origin_id  = "s3-static"
  alb_origin_id = "alb-app"
}

resource "aws_cloudfront_distribution" "cdn" {
  enabled         = true
  comment         = "wsc-cdn"
  is_ipv6_enabled = false
  price_class     = "PriceClass_All"
  web_acl_id      = aws_wafv2_web_acl.waf.arn

  # S3 정적 오리진 (origin_path /static -> /index.html = static/index.html)
  origin {
    origin_id                = local.s3_origin_id
    domain_name              = aws_s3_bucket.static.bucket_regional_domain_name
    origin_path              = "/static"
    origin_access_control_id = aws_cloudfront_origin_access_control.s3.id
  }

  # ALB 앱 오리진 (Ingress가 만든 내부 ALB DNS - var.app_alb_dns)
  origin {
    origin_id   = local.alb_origin_id
    domain_name = var.app_alb_dns
    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  # 기본: 정적 -> S3 (캐싱)
  default_cache_behavior {
    target_origin_id       = local.s3_origin_id
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    cache_policy_id        = data.aws_cloudfront_cache_policy.optimized.id
  }

  # /v1/* -> ALB (비캐싱, 모든 메서드 + 쿼리스트링/헤더 전달)
  ordered_cache_behavior {
    path_pattern             = "/v1/*"
    target_origin_id         = local.alb_origin_id
    viewer_protocol_policy   = "redirect-to-https"
    allowed_methods          = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods           = ["GET", "HEAD"]
    cache_policy_id          = data.aws_cloudfront_cache_policy.disabled.id
    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.all_viewer.id
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = { Name = "wsc-cdn" }
}
