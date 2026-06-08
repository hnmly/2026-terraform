# =============================================================================
# EKS Cluster (wsc-eks-cluster)
#  - v1.35, Workload Subnet, Private endpoint only, KMS secrets, control-plane logging
# =============================================================================

# ---- Cluster IAM Role ----
data "aws_iam_policy_document" "eks_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "eks_cluster" {
  name               = "wsc-eks-cluster-role"
  assume_role_policy = data.aws_iam_policy_document.eks_assume.json
}

resource "aws_iam_role_policy_attachment" "eks_cluster" {
  for_each = toset([
    "arn:${local.partition}:iam::aws:policy/AmazonEKSClusterPolicy",
    "arn:${local.partition}:iam::aws:policy/AmazonEKSVPCResourceController",
  ])
  role       = aws_iam_role.eks_cluster.name
  policy_arn = each.value
}

# ---- Cluster ----
resource "aws_eks_cluster" "this" {
  name     = "wsc-eks-cluster"
  role_arn = aws_iam_role.eks_cluster.arn
  version  = var.eks_version

  vpc_config {
    subnet_ids = [
      aws_subnet.this["workload_a"].id,
      aws_subnet.this["workload_c"].id,
    ]
    endpoint_private_access = true
    endpoint_public_access  = false
  }

  encryption_config {
    provider {
      key_arn = aws_kms_key.main.arn
    }
    resources = ["secrets"]
  }

  enabled_cluster_log_types = [
    "api", "audit", "authenticator", "controllerManager", "scheduler",
  ]

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster,
    aws_cloudwatch_log_group.eks,
  ]

  tags = { Name = "wsc-eks-cluster" }
}

# 컨트롤플레인 로그 그룹 (KMS) - EKS가 생성하기 전에 미리 생성
resource "aws_cloudwatch_log_group" "eks" {
  name              = "/aws/eks/wsc-eks-cluster/cluster"
  retention_in_days = 30
  kms_key_id        = aws_kms_key.main.arn
}

# Bastion -> EKS API(Private endpoint) 443 허용
resource "aws_security_group_rule" "eks_api_from_bastion" {
  type                     = "ingress"
  description              = "Bastion to EKS API"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  security_group_id        = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
  source_security_group_id = aws_security_group.bastion.id
}

# ---- OIDC Provider (IRSA) ----
data "tls_certificate" "oidc" {
  url = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "oidc" {
  url             = aws_eks_cluster.this.identity[0].oidc[0].issuer
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.oidc.certificates[0].sha1_fingerprint]
}
