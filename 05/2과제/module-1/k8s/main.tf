terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.17"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.33"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.19"
    }
  }
}

provider "aws" {
  region = "ap-northeast-2"
}

data "aws_eks_cluster" "main" {
  name = "wsc-scaling-cluster"
}

data "aws_eks_cluster_auth" "main" {
  name = "wsc-scaling-cluster"
}

data "aws_sqs_queue" "main" {
  name = "wsc-scaling-sqs"
}

data "aws_eks_node_group" "main" {
  cluster_name    = "wsc-scaling-cluster"
  node_group_name = "wsc-scaling-node"
}

locals {
  node_role_arn  = data.aws_eks_node_group.main.node_role_arn
  node_role_name = element(split("/", data.aws_eks_node_group.main.node_role_arn), 1)
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.main.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.main.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.main.token
}

provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.main.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.main.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.main.token
  }
}

provider "kubectl" {
  host                   = data.aws_eks_cluster.main.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.main.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.main.token
  load_config_file       = false
}

# Namespace
resource "kubernetes_namespace" "scaling" {
  metadata { name = "wsc-scaling" }
}

# Deployment
resource "kubernetes_deployment" "scaling" {
  metadata {
    name      = "wsc-scaling-deploy"
    namespace = kubernetes_namespace.scaling.metadata[0].name
    labels    = { dedicated = "scaling" }
  }
  spec {
    replicas = 2
    selector { match_labels = { app = "wsc-scaling" } }
    template {
      metadata { labels = { app = "wsc-scaling", dedicated = "scaling" } }
      spec {
        container {
          name    = "busybox"
          image   = "busybox:latest"
          command = ["sleep", "infinity"]
          resources {
            requests = { cpu = "250m", memory = "256Mi" }
            limits   = { cpu = "500m", memory = "512Mi" }
          }
        }
      }
    }
  }
  lifecycle { ignore_changes = [spec[0].replicas] }
}

# KEDA
resource "helm_release" "keda" {
  name             = "keda"
  repository       = "https://kedacore.github.io/charts"
  chart            = "keda"
  namespace        = "keda"
  create_namespace = true
  wait             = true
  timeout          = 600
}

resource "kubectl_manifest" "scaledobject" {
  yaml_body = <<-YAML
    apiVersion: keda.sh/v1alpha1
    kind: ScaledObject
    metadata:
      name: wsc-scaling-scaledobject
      namespace: wsc-scaling
    spec:
      scaleTargetRef:
        name: wsc-scaling-deploy
      pollingInterval: 30
      minReplicaCount: 2
      maxReplicaCount: 20
      triggers:
      - type: aws-sqs-queue
        metadata:
          queueURL: ${data.aws_sqs_queue.main.url}
          queueLength: "5"
          awsRegion: ap-northeast-2
          identityOwner: operator
  YAML
  depends_on = [helm_release.keda, kubernetes_deployment.scaling]
}

# Karpenter
resource "aws_iam_role" "karpenter_controller" {
  name_prefix = "wsc-scaling-karpenter-"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "pods.eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })
}

resource "aws_iam_policy" "karpenter_controller" {
  name_prefix = "wsc-scaling-karpenter-"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:RunInstances", "ec2:CreateFleet", "ec2:CreateLaunchTemplate",
          "ec2:CreateTags", "ec2:TerminateInstances", "ec2:DeleteLaunchTemplate",
          "ec2:DescribeInstances", "ec2:DescribeImages", "ec2:DescribeLaunchTemplates",
          "ec2:DescribeSecurityGroups", "ec2:DescribeSubnets", "ec2:DescribeInstanceTypes",
          "ec2:DescribeInstanceTypeOfferings", "ec2:DescribeAvailabilityZones",
          "ec2:DescribeSpotPriceHistory", "ec2:GetInstanceTypesFromInstanceRequirements"
        ]
        Resource = "*"
      },
      { Effect = "Allow", Action = ["ssm:GetParameter"], Resource = "arn:aws:ssm:*::parameter/aws/service/*" },
      { Effect = "Allow", Action = ["pricing:GetProducts"], Resource = "*" },
      { Effect = "Allow", Action = ["iam:PassRole"], Resource = local.node_role_arn },
      {
        Effect = "Allow"
        Action = ["iam:CreateInstanceProfile", "iam:TagInstanceProfile", "iam:GetInstanceProfile", "iam:AddRoleToInstanceProfile", "iam:RemoveRoleFromInstanceProfile", "iam:DeleteInstanceProfile"]
        Resource = "*"
      },
      { Effect = "Allow", Action = ["eks:DescribeCluster"], Resource = data.aws_eks_cluster.main.arn }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "karpenter_controller" {
  role       = aws_iam_role.karpenter_controller.name
  policy_arn = aws_iam_policy.karpenter_controller.arn
}

resource "aws_eks_pod_identity_association" "karpenter" {
  cluster_name    = data.aws_eks_cluster.main.name
  namespace       = "kube-system"
  service_account = "karpenter"
  role_arn        = aws_iam_role.karpenter_controller.arn
}

resource "helm_release" "karpenter" {
  name       = "karpenter"
  repository = "oci://public.ecr.aws/karpenter"
  chart      = "karpenter"
  version    = "1.0.8"
  namespace  = "kube-system"
  wait       = true
  timeout    = 600
  set {
    name  = "settings.clusterName"
    value = "wsc-scaling-cluster"
  }
  set {
    name  = "settings.clusterEndpoint"
    value = data.aws_eks_cluster.main.endpoint
  }
  set {
    name  = "serviceAccount.name"
    value = "karpenter"
  }
  depends_on = [aws_eks_pod_identity_association.karpenter]
}

resource "kubectl_manifest" "ec2nodeclass" {
  yaml_body = <<-YAML
    apiVersion: karpenter.k8s.aws/v1
    kind: EC2NodeClass
    metadata:
      name: default
    spec:
      role: ${local.node_role_name}
      amiSelectorTerms:
      - alias: al2023@latest
      subnetSelectorTerms:
      - tags:
          karpenter.sh/discovery: wsc-scaling-cluster
      securityGroupSelectorTerms:
      - tags:
          karpenter.sh/discovery: wsc-scaling-cluster
  YAML
  depends_on = [helm_release.karpenter]
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
            values: ["t3.medium", "t3.large"]
          nodeClassRef:
            group: karpenter.k8s.aws
            kind: EC2NodeClass
            name: default
      limits:
        cpu: "100"
        memory: 200Gi
      disruption:
        consolidationPolicy: WhenEmptyOrUnderutilized
        consolidateAfter: 30s
  YAML
  depends_on = [kubectl_manifest.ec2nodeclass]
}
