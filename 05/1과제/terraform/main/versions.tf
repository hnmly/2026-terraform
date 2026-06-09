terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}

# 2단계(Bastion): VPC/Bastion 을 제외한 나머지 전부 생성
provider "aws" {
  region = var.region
  default_tags {
    tags = { Project = "wsc-2026-task1" }
  }
}

# CloudFront / WAF(CLOUDFRONT scope) 용 us-east-1
provider "aws" {
  alias  = "use1"
  region = "us-east-1"
  default_tags {
    tags = { Project = "wsc-2026-task1" }
  }
}
