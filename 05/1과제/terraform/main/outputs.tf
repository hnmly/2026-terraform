output "eks_cluster_name" {
  value = aws_eks_cluster.this.name
}

output "ecr_repository_url" {
  value = aws_ecr_repository.repo.repository_url
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
  value = aws_iam_role.alb.arn
}

output "ebs_csi_role_arn" {
  value = aws_iam_role.ebs.arn
}

output "app_sa_role_arn" {
  value = aws_iam_role.app.arn
}

output "fluentbit_role_arn" {
  value = aws_iam_role.fluentbit.arn
}

output "lambda_arn" {
  value = aws_lambda_function.get_table.arn
}

output "private_subnet_ids" {
  value = [local.subnet_ids["wsc-private-a"], local.subnet_ids["wsc-private-c"]]
}

output "public_subnet_ids" {
  value = [local.subnet_ids["wsc-public-a"], local.subnet_ids["wsc-public-c"]]
}
