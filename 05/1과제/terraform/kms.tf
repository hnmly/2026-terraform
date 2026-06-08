# =============================================================================
# KMS Customer Managed Key (CMK)
#  - DynamoDB / S3 / EKS Secrets / EBS(노드+StorageClass) / ECR / CloudWatch Logs
#    암호화에 공통 사용
# =============================================================================

data "aws_iam_policy_document" "kms" {
  # 계정 루트 전체 권한
  statement {
    sid       = "EnableRoot"
    actions   = ["kms:*"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["arn:${local.partition}:iam::${local.account_id}:root"]
    }
  }

  # CloudWatch Logs 암호화 허용
  statement {
    sid = "AllowCloudWatchLogs"
    actions = [
      "kms:Encrypt*",
      "kms:Decrypt*",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:Describe*",
    ]
    resources = ["*"]
    principals {
      type        = "Service"
      identifiers = ["logs.${var.region}.amazonaws.com"]
    }
    condition {
      test     = "ArnLike"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values   = ["arn:${local.partition}:logs:${var.region}:${local.account_id}:log-group:*"]
    }
  }

  # EBS 볼륨 암호화를 위한 Auto Scaling 서비스 연결 역할 허용 (노드그룹)
  statement {
    sid = "AllowAutoScalingSLR"
    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:CreateGrant",
      "kms:DescribeKey",
    ]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["arn:${local.partition}:iam::${local.account_id}:role/aws-service-role/autoscaling.amazonaws.com/AWSServiceRoleForAutoScaling"]
    }
  }
}

resource "aws_kms_key" "main" {
  description             = "wsc CMK for DynamoDB/S3/EKS/EBS/ECR/Logs"
  deletion_window_in_days = 7
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.kms.json

  tags = {
    Name = "wsc-kms"
  }
}

resource "aws_kms_alias" "main" {
  name          = "alias/wsc-kms"
  target_key_id = aws_kms_key.main.key_id
}
