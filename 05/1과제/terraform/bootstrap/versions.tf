terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
  }
}

# 1단계(로컬): VPC + Bastion 만 생성
provider "aws" {
  region = var.region
  default_tags {
    tags = { Project = "wsc-2026-task1" }
  }
}
