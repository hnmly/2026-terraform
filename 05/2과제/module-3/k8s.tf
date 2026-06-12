# =====================================================================
# Module 3 - 로깅 스택 (Loki / Grafana)
# =====================================================================

# Namespace: wsc-logging
resource "kubernetes_namespace" "logging" {
  metadata {
    name = "wsc-logging"
  }
  depends_on = [aws_eks_node_group.main]
}

# ---------------------------------------------------------------------
# Loki (SingleBinary, filesystem PVC 10Gi)
# ---------------------------------------------------------------------
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

# Loki를 EC2 Fluent Bit이 접근할 수 있도록 NLB(LoadBalancer)로 노출 (port 3100)
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

# ---------------------------------------------------------------------
# Grafana (NLB, Loki DataSource + WSC2026 Container Logs 대시보드)
# ---------------------------------------------------------------------
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
