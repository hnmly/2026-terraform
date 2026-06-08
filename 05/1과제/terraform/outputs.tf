output "bastion_public_ip" {
  description = "Bastion 고정 공인 IP (SSH 접속)"
  value       = aws_eip.bastion.public_ip
}

output "eks_cluster_name" {
  value = aws_eks_cluster.this.name
}

output "ecr_repository_url" {
  description = "ECR 리포지토리 URL (이미지 push 대상)"
  value       = aws_ecr_repository.repo.repository_url
}

output "s3_bucket" {
  value = aws_s3_bucket.static.id
}

output "cloudfront_domain" {
  value = aws_cloudfront_distribution.cdn.domain_name
}

output "kms_key_arn" {
  value = aws_kms_key.main.arn
}

output "alb_controller_role_arn" {
  description = "AWS Load Balancer Controller용 IRSA Role ARN (Helm 설치 시 사용)"
  value       = aws_iam_role.alb.arn
}

output "ebs_csi_role_arn" {
  value = aws_iam_role.ebs.arn
}

output "app_sa_role_arn" {
  description = "App ServiceAccount(wsc-sa) IRSA Role ARN"
  value       = aws_iam_role.app.arn
}

output "fluentbit_role_arn" {
  value = aws_iam_role.fluentbit.arn
}

output "lambda_arn" {
  value = aws_lambda_function.get_table.arn
}

output "private_subnet_ids" {
  value = [aws_subnet.this["private_a"].id, aws_subnet.this["private_c"].id]
}

output "workload_subnet_ids" {
  value = [aws_subnet.this["workload_a"].id, aws_subnet.this["workload_c"].id]
}
