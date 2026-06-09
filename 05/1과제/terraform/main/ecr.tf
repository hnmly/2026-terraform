# =============================================================================
# ECR (wsc-repo) - KMS 암호화, scan on push, 태그 불변
# =============================================================================

resource "aws_ecr_repository" "repo" {
  name                 = "wsc-repo"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = aws_kms_key.main.arn
  }

  tags = { Name = "wsc-repo" }
}

# ---- ECR 이미지 빌드 & 푸시 (Bastion에서 실행 — docker 필수) ----
locals {
  ecr_url    = aws_ecr_repository.repo.repository_url
  ecr_reg    = split("/", aws_ecr_repository.repo.repository_url)[0]
  image_tag  = "v1.0.0"
  docker_dir = "${path.module}/../../docker"
}

resource "null_resource" "ecr_push" {
  triggers = {
    repo       = aws_ecr_repository.repo.repository_url
    dockerfile = filemd5("${local.docker_dir}/Dockerfile")
    book       = filemd5("${local.docker_dir}/book")
  }

  provisioner "local-exec" {
    command = <<-EOT
      aws ecr get-login-password --region ${var.region} | docker login --username AWS --password-stdin ${local.ecr_reg}
      docker buildx build --platform linux/amd64 -t ${local.ecr_url}:${local.image_tag} --push ${local.docker_dir}
    EOT
  }

  depends_on = [aws_ecr_repository.repo]
}
