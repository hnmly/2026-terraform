# =============================================================================
# CloudFront VPC Origin — internal ALB를 CloudFront origin으로 사용
#  internal ALB는 인터넷에서 DNS 해석이 안 되므로 VPC Origin으로 연결한다.
# =============================================================================
resource "aws_cloudfront_vpc_origin" "app" {
  vpc_origin_endpoint_config {
    name                   = "wsc-app-vpc-origin"
    arn                    = aws_lb.app.arn
    http_port              = 80
    https_port             = 443
    origin_protocol_policy = "http-only"

    origin_ssl_protocols {
      items    = ["TLSv1.2"]
      quantity = 1
    }
  }
}
