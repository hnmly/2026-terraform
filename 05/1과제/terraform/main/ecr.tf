# =============================================================================
# ECR (wsc-repo) - KMS 암호화, scan on push, 태그 불변
# =============================================================================

resource "aws_ecr_repository" "repo" {
  name                 = "wsc-repo"
  image_tag_mutability = "IMMUTABLE"
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
