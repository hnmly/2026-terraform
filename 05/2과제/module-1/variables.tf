variable "bastion_ami" {
  description = "Bastion EC2에 사용할 AMI ID (서울 리전 ap-northeast-2 전용 커스텀 이미지)"
  type        = string
  default     = "ami-00e1a894b4512388e"
}
