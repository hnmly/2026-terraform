# =============================================================================
# S3 (정적 콘텐츠)  - wsc-static-<ACCOUNT_ID>, SSE-KMS, /static 업로드
# =============================================================================

resource "aws_s3_bucket" "static" {
  bucket        = local.bucket_name
  force_destroy = true
  tags          = { Name = local.bucket_name }
}

resource "aws_s3_bucket_public_access_block" "static" {
  bucket                  = aws_s3_bucket.static.id
  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "static" {
  bucket = aws_s3_bucket.static.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.main.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_object" "static" {
  for_each = {
    "static/index.html" = { src = "../../docker/static/index.html", ct = "text/html" }
    "static/main.jpeg"  = { src = "../../docker/static/main.jpeg", ct = "image/jpeg" }
  }

  bucket                 = aws_s3_bucket.static.id
  key                    = each.key
  source                 = "${path.module}/${each.value.src}"
  source_hash            = filemd5("${path.module}/${each.value.src}")
  content_type           = each.value.ct
  server_side_encryption = "aws:kms"
  kms_key_id             = aws_kms_key.main.arn

  depends_on = [aws_s3_bucket_server_side_encryption_configuration.static]
}

# CloudFront OAC 접근용 버킷 정책 (cloudfront.tf의 distribution 참조)
data "aws_iam_policy_document" "static_bucket" {
  statement {
    sid       = "AllowCloudFrontOAC"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.static.arn}/*"]
    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.cdn.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "static" {
  bucket     = aws_s3_bucket.static.id
  policy     = data.aws_iam_policy_document.static_bucket.json
  depends_on = [aws_s3_bucket_public_access_block.static]
}
