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

variable "dockerhub_secret_arn" {
  description = "Docker Hub pull-through cache용 Secrets Manager ARN (grafana 등 docker.io 이미지). 없으면 Docker Hub 캐시 미생성."
  type        = string
  default     = ""
}
