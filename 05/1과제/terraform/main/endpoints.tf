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
  vpc_id      = local.vpc_id

  ingress {
    description = "All traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
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
  # private DNS 지원되는 표준 인터페이스 엔드포인트
  interface_endpoints = [
    "ec2",
    "ecr.api",
    "ecr.dkr",
    "sts",
    "logs",
    "elasticloadbalancing",
    "autoscaling",
  ]
}

resource "aws_vpc_endpoint" "interface" {
  for_each = toset(local.interface_endpoints)

  vpc_id              = local.vpc_id
  service_name        = "com.amazonaws.${var.region}.${each.key}"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  security_group_ids  = [aws_security_group.vpce.id]
  subnet_ids          = [local.subnet_ids["wsc-workload-a"], local.subnet_ids["wsc-workload-c"]]

  tags = { Name = "wsc-vpce-${replace(each.key, ".", "-")}" }
}

# S3 Interface Endpoint (Gateway 불가 - workload RT 라우트 0개 유지)
#  - private DNS 활성화 시 VPC 전체 적용을 위해 inbound-resolver 전용 옵션을 false로
resource "aws_vpc_endpoint" "s3" {
  vpc_id              = local.vpc_id
  service_name        = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  security_group_ids  = [aws_security_group.vpce.id]
  subnet_ids          = [local.subnet_ids["wsc-workload-a"], local.subnet_ids["wsc-workload-c"]]

  dns_options {
    private_dns_only_for_inbound_resolver_endpoint = false
  }

  tags = { Name = "wsc-vpce-s3" }
}

# DynamoDB Interface Endpoint (private DNS 미지원 -> 비활성화)
resource "aws_vpc_endpoint" "dynamodb" {
  vpc_id              = local.vpc_id
  service_name        = "com.amazonaws.${var.region}.dynamodb"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = false
  security_group_ids  = [aws_security_group.vpce.id]
  subnet_ids          = [local.subnet_ids["wsc-workload-a"], local.subnet_ids["wsc-workload-c"]]

  tags = { Name = "wsc-vpce-dynamodb" }
}