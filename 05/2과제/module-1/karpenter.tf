# =====================================================================
# Module 1 - Karpenter (Node 자동 확장)
# =====================================================================

locals {
  karpenter_version = "1.0.8"
}

# 클러스터 보안 그룹에 Karpenter 디스커버리 태그 부여
resource "aws_ec2_tag" "cluster_sg_discovery" {
  resource_id = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
  key         = "karpenter.sh/discovery"
  value       = "wsc-scaling-cluster"
}

# ---------------------------------------------------------------------
# Karpenter Controller IAM Role (EKS Pod Identity)
# ---------------------------------------------------------------------
resource "aws_iam_role" "karpenter_controller" {
  name = "${local.name}-karpenter-controller"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "pods.eks.amazonaws.com"
      }
      Action = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })
}

resource "aws_iam_policy" "karpenter_controller" {
  name = "${local.name}-karpenter-controller"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EC2Actions"
        Effect = "Allow"
        Action = [
          "ec2:RunInstances",
          "ec2:CreateFleet",
          "ec2:CreateLaunchTemplate",
          "ec2:CreateTags",
          "ec2:TerminateInstances",
          "ec2:DeleteLaunchTemplate",
          "ec2:DescribeInstances",
          "ec2:DescribeImages",
          "ec2:DescribeLaunchTemplates",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeSubnets",
          "ec2:DescribeInstanceTypes",
          "ec2:DescribeInstanceTypeOfferings",
          "ec2:DescribeAvailabilityZones",
          "ec2:DescribeSpotPriceHistory",
          "ec2:GetInstanceTypesFromInstanceRequirements"
        ]
        Resource = "*"
      },
      {
        Sid      = "SSMParameters"
        Effect   = "Allow"
        Action   = ["ssm:GetParameter"]
        Resource = "arn:aws:ssm:*::parameter/aws/service/*"
      },
      {
        Sid      = "PricingAPI"
        Effect   = "Allow"
        Action   = ["pricing:GetProducts"]
        Resource = "*"
      },
      {
        Sid      = "PassNodeRole"
        Effect   = "Allow"
        Action   = ["iam:PassRole"]
        Resource = aws_iam_role.eks_node.arn
      },
      {
        Sid    = "InstanceProfile"
        Effect = "Allow"
        Action = [
          "iam:CreateInstanceProfile",
          "iam:TagInstanceProfile",
          "iam:GetInstanceProfile",
          "iam:AddRoleToInstanceProfile",
          "iam:RemoveRoleFromInstanceProfile",
          "iam:DeleteInstanceProfile"
        ]
        Resource = "*"
      },
      {
        Sid      = "EKSCluster"
        Effect   = "Allow"
        Action   = ["eks:DescribeCluster"]
        Resource = aws_eks_cluster.main.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "karpenter_controller" {
  role       = aws_iam_role.karpenter_controller.name
  policy_arn = aws_iam_policy.karpenter_controller.arn
}

# Karpenter Controller ServiceAccount <-> IAM Role 연결 (Pod Identity)
resource "aws_eks_pod_identity_association" "karpenter" {
  cluster_name    = aws_eks_cluster.main.name
  namespace       = "kube-system"
  service_account = "karpenter"
  role_arn        = aws_iam_role.karpenter_controller.arn

  depends_on = [aws_eks_addon.pod_identity]
}

# Karpenter 노드는 관리형 노드그룹과 동일한 노드 역할(eks_node)을 사용하므로,
# 노드그룹이 자동 생성하는 EC2_LINUX access entry를 그대로 활용한다.
# (별도 access entry 생성 시 중복 오류 발생)

# ---------------------------------------------------------------------
# Karpenter 설치 (Helm)
# ---------------------------------------------------------------------
resource "helm_release" "karpenter" {
  name       = "karpenter"
  repository = "oci://public.ecr.aws/karpenter"
  chart      = "karpenter"
  version    = local.karpenter_version
  namespace  = "kube-system"
  wait       = true
  timeout    = 600

  set {
    name  = "settings.clusterName"
    value = aws_eks_cluster.main.name
  }

  set {
    name  = "settings.clusterEndpoint"
    value = aws_eks_cluster.main.endpoint
  }

  set {
    name  = "serviceAccount.name"
    value = "karpenter"
  }

  # 컨트롤러는 관리형 노드그룹에서만 동작하도록 (자기 자신이 만든 노드 회피)
  set {
    name  = "controller.resources.requests.cpu"
    value = "200m"
  }
  set {
    name  = "controller.resources.requests.memory"
    value = "256Mi"
  }

  depends_on = [
    aws_eks_node_group.main,
    aws_eks_pod_identity_association.karpenter,
  ]
}

# ---------------------------------------------------------------------
# EC2NodeClass + NodePool
# ---------------------------------------------------------------------
resource "kubectl_manifest" "ec2nodeclass" {
  yaml_body = <<-YAML
    apiVersion: karpenter.k8s.aws/v1
    kind: EC2NodeClass
    metadata:
      name: default
    spec:
      role: ${aws_iam_role.eks_node.name}
      amiSelectorTerms:
      - alias: al2023@latest
      subnetSelectorTerms:
      - tags:
          karpenter.sh/discovery: wsc-scaling-cluster
      securityGroupSelectorTerms:
      - tags:
          karpenter.sh/discovery: wsc-scaling-cluster
  YAML

  depends_on = [
    helm_release.karpenter,
    aws_ec2_tag.cluster_sg_discovery,
  ]
}

resource "kubectl_manifest" "nodepool" {
  yaml_body = <<-YAML
    apiVersion: karpenter.sh/v1
    kind: NodePool
    metadata:
      name: wsc-scaling-nodepool
    spec:
      template:
        metadata:
          labels:
            dedicated: scaling
        spec:
          requirements:
          - key: kubernetes.io/arch
            operator: In
            values: ["amd64"]
          - key: karpenter.sh/capacity-type
            operator: In
            values: ["on-demand"]
          - key: node.kubernetes.io/instance-type
            operator: In
            values: ["t3.medium", "t3.large", "t3.xlarge"]
          nodeClassRef:
            group: karpenter.k8s.aws
            kind: EC2NodeClass
            name: default
          expireAfter: 720h
      limits:
        cpu: "100"
        memory: 200Gi
      disruption:
        consolidationPolicy: WhenEmptyOrUnderutilized
        consolidateAfter: 30s
  YAML

  depends_on = [kubectl_manifest.ec2nodeclass]
}
