variable "region" {
  default = "ap-northeast-2"
}

variable "bibunho" {
  description = "선수 비번호"
  type        = string
}

variable "origin_verify_value" {
  description = "CloudFront Origin Custom Header Value (20자 이상)"
  default     = "SkillsKorea2026SecureHeaderValue"
}
