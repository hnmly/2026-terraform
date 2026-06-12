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
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}

provider "aws" {
  region = "ap-northeast-1"
}

variable "pin" {
  description = "비번호 (Grafana 계정). 예: terraform apply -var pin=07"
  type        = string
  default     = "00"
}

data "aws_eks_cluster" "main" {
  name = "wsc-logging-cluster"
}

data "aws_eks_cluster_auth" "main" {
  name = "wsc-logging-cluster"
}

data "aws_instance" "app" {
  filter {
    name   = "tag:Name"
    values = ["wsc-logging-app-bastion"]
  }
  filter {
    name   = "instance-state-name"
    values = ["running"]
  }
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

# 기본 StorageClass (gp3)
resource "kubernetes_storage_class" "gp3" {
  metadata {
    name = "gp3"
    annotations = {
      "storageclass.kubernetes.io/is-default-class" = "true"
    }
  }
  storage_provisioner    = "ebs.csi.aws.com"
  volume_binding_mode    = "WaitForFirstConsumer"
  allow_volume_expansion = true
  parameters = {
    type = "gp3"
  }
}

# Namespace
resource "kubernetes_namespace" "logging" {
  metadata {
    name = "wsc-logging"
  }
}

# Loki (SingleBinary, filesystem PVC 10Gi)
resource "helm_release" "loki" {
  name       = "loki"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "loki"
  version    = "6.18.0"
  namespace  = kubernetes_namespace.logging.metadata[0].name
  wait       = true
  timeout    = 900

  values = [<<-YAML
    loki:
      auth_enabled: false
      commonConfig:
        replication_factor: 1
      storage:
        type: filesystem
      schemaConfig:
        configs:
        - from: "2024-04-01"
          store: tsdb
          object_store: filesystem
          schema: v13
          index:
            prefix: index_
            period: 24h
      limits_config:
        retention_period: 168h
        allow_structured_metadata: true
      pattern_ingester:
        enabled: false
    deploymentMode: SingleBinary
    singleBinary:
      replicas: 1
      persistence:
        enabled: true
        size: 10Gi
        storageClass: gp3
    read:
      replicas: 0
    write:
      replicas: 0
    backend:
      replicas: 0
    chunksCache:
      enabled: false
    resultsCache:
      enabled: false
    gateway:
      enabled: false
    test:
      enabled: false
    lokiCanary:
      enabled: false
    monitoring:
      selfMonitoring:
        enabled: false
        grafanaAgent:
          installOperator: false
  YAML
  ]

  depends_on = [kubernetes_storage_class.gp3]
}

# Loki NLB 노출 (EC2 Fluent Bit용, port 3100)
resource "kubernetes_service" "loki_nlb" {
  metadata {
    name      = "loki-nlb"
    namespace = kubernetes_namespace.logging.metadata[0].name
    labels = {
      "app.kubernetes.io/name" = "loki"
    }
    annotations = {
      "service.beta.kubernetes.io/aws-load-balancer-type" = "nlb"
    }
  }
  spec {
    type = "LoadBalancer"
    selector = {
      "app.kubernetes.io/name"      = "loki"
      "app.kubernetes.io/component" = "single-binary"
    }
    port {
      name        = "http"
      port        = 3100
      target_port = 3100
    }
  }
  depends_on = [helm_release.loki]
}

# Grafana (NLB, Loki DataSource + WSC2026 Container Logs 대시보드)
resource "helm_release" "grafana" {
  name       = "grafana"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "grafana"
  version    = "8.5.1"
  namespace  = kubernetes_namespace.logging.metadata[0].name
  wait       = true
  timeout    = 600

  values = [<<-YAML
    adminUser: wsc2026-admin-${var.pin}
    adminPassword: admin${var.pin}!
    service:
      type: LoadBalancer
      port: 80
      annotations:
        service.beta.kubernetes.io/aws-load-balancer-type: "nlb"
    datasources:
      datasources.yaml:
        apiVersion: 1
        datasources:
        - name: Loki
          type: loki
          uid: loki
          access: proxy
          url: http://loki.wsc-logging.svc.cluster.local:3100
          isDefault: true
    dashboardProviders:
      dashboardproviders.yaml:
        apiVersion: 1
        providers:
        - name: default
          orgId: 1
          folder: ''
          type: file
          disableDeletion: false
          editable: true
          options:
            path: /var/lib/grafana/dashboards/default
    dashboards:
      default:
        wsc2026-container-logs:
          json: |
            {
              "title": "WSC2026 Container Logs",
              "uid": "wsc2026-logs",
              "schemaVersion": 39,
              "time": { "from": "now-1h", "to": "now" },
              "refresh": "5s",
              "panels": [
                {
                  "id": 1,
                  "title": "Any Log",
                  "type": "logs",
                  "gridPos": { "h": 8, "w": 24, "x": 0, "y": 0 },
                  "datasource": { "type": "loki", "uid": "loki" },
                  "targets": [ { "refId": "A", "expr": "{namespace=\"wsc-app-log\"}" } ]
                },
                {
                  "id": 2,
                  "title": "INFO Log Count",
                  "type": "timeseries",
                  "gridPos": { "h": 8, "w": 8, "x": 0, "y": 8 },
                  "datasource": { "type": "loki", "uid": "loki" },
                  "targets": [ { "refId": "A", "expr": "count_over_time({namespace=\"wsc-app-log\"} |= \"INFO\" [1m])" } ]
                },
                {
                  "id": 3,
                  "title": "ERROR Log Count",
                  "type": "timeseries",
                  "gridPos": { "h": 8, "w": 8, "x": 8, "y": 8 },
                  "datasource": { "type": "loki", "uid": "loki" },
                  "targets": [ { "refId": "A", "expr": "count_over_time({namespace=\"wsc-app-log\"} |= \"ERROR\" [1m])" } ]
                },
                {
                  "id": 4,
                  "title": "WARNING Log Count",
                  "type": "timeseries",
                  "gridPos": { "h": 8, "w": 8, "x": 16, "y": 8 },
                  "datasource": { "type": "loki", "uid": "loki" },
                  "targets": [ { "refId": "A", "expr": "count_over_time({namespace=\"wsc-app-log\"} |= \"WARNING\" [1m])" } ]
                }
              ]
            }
  YAML
  ]

  depends_on = [helm_release.loki]
}

# EC2 Fluent Bit에 Loki NLB 엔드포인트 자동 주입 (SSM)
resource "null_resource" "configure_fluentbit" {
  triggers = {
    loki_host   = kubernetes_service.loki_nlb.status[0].load_balancer[0].ingress[0].hostname
    instance_id = data.aws_instance.app.id
  }

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = <<-EOT
      set -e
      LOKI_HOST="${kubernetes_service.loki_nlb.status[0].load_balancer[0].ingress[0].hostname}"
      INSTANCE_ID="${data.aws_instance.app.id}"
      echo "Loki NLB: $LOKI_HOST -> instance $INSTANCE_ID"
      for i in $(seq 1 30); do
        PING=$(aws ssm describe-instance-information --region ap-northeast-1 \
          --filters "Key=InstanceIds,Values=$INSTANCE_ID" \
          --query "InstanceInformationList[0].PingStatus" --output text 2>/dev/null || echo "None")
        [ "$PING" = "Online" ] && break
        echo "SSM not ready ($PING), retry $i..."; sleep 10
      done
      CMD_ID=$(aws ssm send-command --region ap-northeast-1 \
        --instance-ids "$INSTANCE_ID" \
        --document-name "AWS-RunShellScript" \
        --parameters "commands=[\"sed -i \\\"s/LOKI_NLB_DNS/$LOKI_HOST/g\\\" /etc/fluent-bit/fluent-bit.conf\",\"systemctl restart fluent-bit\",\"systemctl is-active fluent-bit\"]" \
        --query "Command.CommandId" --output text)
      echo "SSM Command: $CMD_ID"
      sleep 10
      aws ssm get-command-invocation --region ap-northeast-1 \
        --command-id "$CMD_ID" --instance-id "$INSTANCE_ID" \
        --query "StandardOutputContent" --output text || true
    EOT
  }

  depends_on = [kubernetes_service.loki_nlb]
}