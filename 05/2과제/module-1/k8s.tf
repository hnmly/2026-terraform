# =====================================================================
# Module 1 - Kubernetes 워크로드 (Namespace / Deployment / KEDA)
# =====================================================================

# Namespace: wsc-scaling
resource "kubernetes_namespace" "scaling" {
  metadata {
    name = "wsc-scaling"
  }
  depends_on = [aws_eks_node_group.main]
}

# Deployment: wsc-scaling-deploy (busybox, sleep)
resource "kubernetes_deployment" "scaling" {
  metadata {
    name      = "wsc-scaling-deploy"
    namespace = kubernetes_namespace.scaling.metadata[0].name
    labels = {
      dedicated = "scaling"
    }
  }

  spec {
    replicas = 2

    selector {
      match_labels = {
        app = "wsc-scaling"
      }
    }

    template {
      metadata {
        labels = {
          app       = "wsc-scaling"
          dedicated = "scaling"
        }
      }

      spec {
        container {
          name    = "busybox"
          image   = "busybox:latest"
          command = ["sleep", "infinity"]

          resources {
            requests = {
              cpu    = "250m"
              memory = "256Mi"
            }
            limits = {
              cpu    = "500m"
              memory = "512Mi"
            }
          }
        }
      }
    }
  }

  # KEDA가 replicas를 관리하므로 이후 변경은 무시
  lifecycle {
    ignore_changes = [spec[0].replicas]
  }
}

# KEDA 설치 (Helm)
resource "helm_release" "keda" {
  name             = "keda"
  repository       = "https://kedacore.github.io/charts"
  chart            = "keda"
  namespace        = "keda"
  create_namespace = true
  wait             = true
  timeout          = 600

  depends_on = [aws_eks_node_group.main]
}

# KEDA ScaledObject: SQS 기반 스케일링
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
          queueURL: ${aws_sqs_queue.main.url}
          queueLength: "5"
          awsRegion: ap-northeast-2
          identityOwner: operator
  YAML

  depends_on = [
    helm_release.keda,
    kubernetes_deployment.scaling,
    aws_iam_role_policy_attachment.node_keda_sqs,
  ]
}
