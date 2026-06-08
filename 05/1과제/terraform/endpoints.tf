# =============================================================================
# VPC Endpoints (Interface)
#  - Workload Subnet은 인터넷 라우트가 없으므로(라우트 테이블 규칙 0개),
#    AWS 서비스 접근은 Interface Endpoint(ENI)로 수행한다.
#  - Gateway Endpoint(S3/DynamoDB)는 라우트 테이블에 경로를 추가하므로 사용하지 않고,
#    모두 Interface Endpoint로 구성한다.
# =============================================================================

resource "aws_security_group" "vpce" {
  name        = "wsc-vpce-sg"
  description = "Allow HTTPS from VPC to interface endpoints"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTPS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.main.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "wsc-vpce-sg" }
}

locals {
  interface_endpoints = [
    "ec2",
    "ecr.api",
    "ecr.dkr",
    "s3",
    "sts",
    "logs",
    "elasticloadbalancing",
    "autoscaling",
    "dynamodb",
  ]
}

resource "aws_vpc_endpoint" "interface" {
  for_each = toset(local.interface_endpoints)

  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.region}.${each.key}"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  security_group_ids  = [aws_security_group.vpce.id]
  subnet_ids          = [aws_subnet.this["workload_a"].id, aws_subnet.this["workload_c"].id]

  tags = { Name = "wsc-vpce-${replace(each.key, ".", "-")}" }
}
