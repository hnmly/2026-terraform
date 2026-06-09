variable "region" {
  description = "AWS 리전 (문제 고정: ap-northeast-2)"
  type        = string
  default     = "ap-northeast-2"
}

variable "azs" {
  description = "사용할 가용영역 2개 (a, c)"
  type        = list(string)
  default     = ["ap-northeast-2a", "ap-northeast-2c"]
}

variable "eks_version" {
  description = "EKS 클러스터 버전"
  type        = string
  default     = "1.35"
}

variable "node_instance_type" {
  description = "노드그룹 인스턴스 타입"
  type        = string
  default     = "t3.medium"
}

variable "bastion_instance_type" {
  description = "Bastion 인스턴스 타입"
  type        = string
  default     = "t3.medium"
}

variable "bastion_ami" {
  description = "Bastion AMI (Amazon Linux 2023 x86_64, ap-northeast-2). SSM 조회 권한 불필요하도록 고정."
  type        = string
  default     = "ami-00e1a894b4512388e"
}

variable "ssh_password" {
  description = "Bastion 및 노드 SSH 패스워드 (채점용)"
  type        = string
  default     = "Skill53##"
  sensitive   = true
}

variable "image_tag" {
  description = "ECR 이미지 태그"
  type        = string
  default     = "v1.0.0"
}

variable "app_alb_dns" {
  description = <<-EOT
    wsc-app-lb(Ingress가 생성하는 내부 ALB)의 DNS 이름.
    EKS+ALB Controller+Ingress 배포 후 생성되므로 2단계로 적용한다.
    1단계: 이 값을 비운 채(placeholder) 인프라를 만들고 K8s를 배포,
    2단계: 생성된 ALB DNS를 이 변수에 넣고 apply 하여 CloudFront origin 연결.
  EOT
  type        = string
  default     = "placeholder-app-lb.elb.amazonaws.com"
}
