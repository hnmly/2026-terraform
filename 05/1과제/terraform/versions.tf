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

# 모든 리소스는 서울(ap-northeast-2) 리전
provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project = "wsc-2026-task1"
    }
  }
}

# CloudFront WAF(CLOUDFRONT scope) 및 CloudFront는 us-east-1 필요
provider "aws" {
  alias  = "use1"
  region = "us-east-1"

  default_tags {
    tags = {
      Project = "wsc-2026-task1"
    }
  }
}
