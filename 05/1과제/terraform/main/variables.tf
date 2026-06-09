variable "region" {
  type    = string
  default = "ap-northeast-2"
}

variable "eks_version" {
  type    = string
  default = "1.35"
}

variable "node_instance_type" {
  type    = string
  default = "t3.medium"
}

variable "ssh_password" {
  description = "노드 SSH 패스워드 (채점용)"
  type        = string
  default     = "Skill53##"
  sensitive   = true
}

variable "image_tag" {
  type    = string
  default = "v1.0.0"
}

variable "app_alb_dns" {
  description = <<-EOT
    wsc-app-lb(Ingress가 생성하는 내부 ALB)의 DNS. K8s 배포 후 생성되므로 그 후 값 주입.
    그 전에는 placeholder로 두고 CloudFront만 임시 생성.
  EOT
  type        = string
  default     = "placeholder-app-lb.elb.amazonaws.com"
}
