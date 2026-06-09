variable "region" {
  type    = string
  default = "ap-northeast-2"
}

variable "azs" {
  type    = list(string)
  default = ["ap-northeast-2a", "ap-northeast-2c"]
}

variable "bastion_instance_type" {
  type    = string
  default = "t3.medium"
}

variable "ssh_password" {
  description = "Bastion SSH 패스워드 (채점용)"
  type        = string
  default     = "Skill53##"
  sensitive   = true
}
