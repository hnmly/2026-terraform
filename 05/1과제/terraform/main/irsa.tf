# =============================================================================
# IRSA (IAM Roles for Service Accounts)
#  - app(wsc/wsc-sa): DynamoDB 접근 (Pod는 노드 IAM 사용 금지)
#  - AWS Load Balancer Controller (kube-system/aws-load-balancer-controller)
#  - EBS CSI Driver (kube-system/ebs-csi-controller-sa)
#  - Fluent Bit (logging/fluent-bit)
# =============================================================================

locals {
  oidc_arn = aws_iam_openid_connect_provider.oidc.arn
  oidc_url = replace(aws_eks_cluster.this.identity[0].oidc[0].issuer, "https://", "")
}

# IRSA assume-role 정책 생성 헬퍼
data "aws_iam_policy_document" "irsa" {
  for_each = {
    app       = "system:serviceaccount:wsc:wsc-sa"
    alb       = "system:serviceaccount:kube-system:aws-load-balancer-controller"
    ebs       = "system:serviceaccount:kube-system:ebs-csi-controller-sa"
    fluentbit = "system:serviceaccount:logging:fluent-bit"
  }

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"
    principals {
      type        = "Federated"
      identifiers = [local.oidc_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_url}:sub"
      values   = [each.value]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

# ---- App SA Role (DynamoDB) ----
resource "aws_iam_role" "app" {
  name_prefix        = "wsc-app-sa-role-"
  assume_role_policy = data.aws_iam_policy_document.irsa["app"].json
}

data "aws_iam_policy_document" "app" {
  statement {
    sid = "DynamoDB"
    actions = [
      "dynamodb:PutItem", "dynamodb:GetItem", "dynamodb:Query",
      "dynamodb:UpdateItem", "dynamodb:Scan", "dynamodb:BatchWriteItem",
      "dynamodb:DescribeTable",
    ]
    resources = [aws_dynamodb_table.table.arn, "${aws_dynamodb_table.table.arn}/index/*"]
  }
  statement {
    sid       = "KMS"
    actions   = ["kms:Encrypt", "kms:Decrypt", "kms:GenerateDataKey", "kms:DescribeKey"]
    resources = [aws_kms_key.main.arn]
  }
}

resource "aws_iam_role_policy" "app" {
  name   = "wsc-app-dynamodb"
  role   = aws_iam_role.app.id
  policy = data.aws_iam_policy_document.app.json
}

# ---- AWS Load Balancer Controller Role ----
resource "aws_iam_role" "alb" {
  name_prefix        = "wsc-alb-controller-role-"
  assume_role_policy = data.aws_iam_policy_document.irsa["alb"].json
}

resource "aws_iam_policy" "alb" {
  name_prefix = "wsc-alb-controller-policy-"
  policy      = file("${path.module}/policies/alb-controller-policy.json")
}

resource "aws_iam_role_policy_attachment" "alb" {
  role       = aws_iam_role.alb.name
  policy_arn = aws_iam_policy.alb.arn
}

# ---- EBS CSI Driver Role ----
resource "aws_iam_role" "ebs" {
  name_prefix        = "wsc-ebs-csi-role-"
  assume_role_policy = data.aws_iam_policy_document.irsa["ebs"].json
}

resource "aws_iam_role_policy_attachment" "ebs_managed" {
  role       = aws_iam_role.ebs.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

# EBS CSI가 CMK로 볼륨 암호화에 사용
data "aws_iam_policy_document" "ebs_kms" {
  statement {
    actions   = ["kms:CreateGrant", "kms:Encrypt", "kms:Decrypt", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:DescribeKey"]
    resources = [aws_kms_key.main.arn]
  }
}

resource "aws_iam_role_policy" "ebs_kms" {
  name   = "wsc-ebs-kms"
  role   = aws_iam_role.ebs.id
  policy = data.aws_iam_policy_document.ebs_kms.json
}

# ---- Fluent Bit Role (CloudWatch Logs) ----
resource "aws_iam_role" "fluentbit" {
  name_prefix        = "wsc-fluentbit-role-"
  assume_role_policy = data.aws_iam_policy_document.irsa["fluentbit"].json
}

data "aws_iam_policy_document" "fluentbit" {
  statement {
    sid = "Logs"
    actions = [
      "logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents",
      "logs:DescribeLogGroups", "logs:DescribeLogStreams", "logs:PutRetentionPolicy",
    ]
    resources = ["*"]
  }
  statement {
    sid       = "KMS"
    actions   = ["kms:Encrypt", "kms:Decrypt", "kms:GenerateDataKey", "kms:DescribeKey"]
    resources = [aws_kms_key.main.arn]
  }
}

resource "aws_iam_role_policy" "fluentbit" {
  name   = "wsc-fluentbit-logs"
  role   = aws_iam_role.fluentbit.id
  policy = data.aws_iam_policy_document.fluentbit.json
}
