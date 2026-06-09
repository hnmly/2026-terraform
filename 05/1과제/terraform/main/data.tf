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

# Bastion 역할은 이름이 name_prefix로 랜덤이므로, Bastion 인스턴스의
# 인스턴스 프로파일을 통해 역할 ARN을 발견한다 (고정 이름 의존 X).
data "aws_instance" "bastion" {
  filter {
    name   = "tag:Name"
    values = ["wsc-bastion"]
  }
  filter {
    name   = "instance-state-name"
    values = ["running"]
  }
}

data "aws_iam_instance_profile" "bastion" {
  name = data.aws_instance.bastion.iam_instance_profile
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

  bastion_role_arn = data.aws_iam_instance_profile.bastion.role_arn

  # 서브넷 ID 단축 참조
  subnet_ids = { for k, v in data.aws_subnet.lookup : k => v.id }
}
