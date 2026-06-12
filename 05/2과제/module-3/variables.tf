variable "pin" {
  description = "비번호 (Grafana admin 계정에 사용). 예: terraform apply -var pin=07"
  type        = string
  default     = "00"
}
