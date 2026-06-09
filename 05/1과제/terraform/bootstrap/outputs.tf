output "vpc_id" {
  value = aws_vpc.main.id
}

output "bastion_public_ip" {
  description = "Bastion 고정 공인 IP (SSH 접속)"
  value       = aws_eip.bastion.public_ip
}

output "bastion_role_arn" {
  value = aws_iam_role.bastion.arn
}

output "workload_subnet_ids" {
  value = [aws_subnet.this["workload_a"].id, aws_subnet.this["workload_c"].id]
}

output "private_subnet_ids" {
  value = [aws_subnet.this["private_a"].id, aws_subnet.this["private_c"].id]
}

output "public_subnet_ids" {
  value = [aws_subnet.this["public_a"].id, aws_subnet.this["public_c"].id]
}
