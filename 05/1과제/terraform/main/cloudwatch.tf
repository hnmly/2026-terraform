# =============================================================================
# CloudWatch Logs (/wsc/pod/log) - KMS 암호화 (Fluent Bit가 사용)
# =============================================================================

resource "aws_cloudwatch_log_group" "pod" {
  name              = "/wsc/pod/log"
  retention_in_days = 30
  kms_key_id        = aws_kms_key.main.arn

  tags = { Name = "wsc-pod-log" }
}

# =============================================================================
# EKS Access Entry - Bastion Role을 클러스터 관리자로 등록
#  (Bastion에서 kubectl 사용 가능)
# =============================================================================

resource "aws_eks_access_entry" "bastion" {
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = data.aws_iam_role.bastion.arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "bastion_admin" {
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = data.aws_iam_role.bastion.arn
  policy_arn    = "arn:${local.partition}:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.bastion]
}