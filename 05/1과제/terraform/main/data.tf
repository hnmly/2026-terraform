# =============================================================================
# 1단계(bootstrap)에서 만든 VPC/서브넷/Bastion 을 "조회만" 한다 (재생성 X).
#  - 태그 Name 기준으로 lookup → main 은 이들을 절대 새로 만들지 않는다.
# =============================================================================

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

data "aws_vpc" "main" {
  filter {
    name   = "tag:Name"
    values = ["wsc-vpc"]
  }
}

data "aws_subnet" "lookup" {
  for_each = toset([
    "wsc-public-a", "wsc-public-c",
    "wsc-private-a", "wsc-private-c",
    "wsc-workload-a", "wsc-workload-c",
  ])
  vpc_id = data.aws_vpc.main.id
  filter {
    name   = "tag:Name"
    values = [each.key]
  }
}

data "aws_security_group" "bastion" {
  filter {
    name   = "tag:Name"
    values = ["wsc-bastion-sg"]
  }
  vpc_id = data.aws_vpc.main.id
}

data "aws_iam_role" "bastion" {
  name = "wsc-bastion-role"
}

# EC2 서비스 assume-role 정책 (노드 역할용 - 원래 bastion.tf에 있던 것)
data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

locals {
  account_id  = data.aws_caller_identity.current.account_id
  partition   = data.aws_partition.current.partition
  bucket_name = "wsc-static-${local.account_id}"

  vpc_id     = data.aws_vpc.main.id
  vpc_cidr   = data.aws_vpc.main.cidr_block
  bastion_sg = data.aws_security_group.bastion.id

  # 서브넷 ID 단축 참조
  subnet_ids = { for k, v in data.aws_subnet.lookup : k => v.id }
}
