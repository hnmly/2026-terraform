# 05 2과제 - 1모듈(EKS Scaling) / 3모듈(Container Logging)

## 사전 준비 (CloudShell)

```bash
# Terraform 설치
sudo yum install -y yum-utils
sudo yum-config-manager --add-repo https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo
sudo yum -y install terraform
terraform --version
```

## 실행 방법 (CloudShell)

### 1모듈 - EKS Scaling (ap-northeast-2)

```bash
# 코드 다운로드
cd ~
git clone https://github.com/hnmly/2026-terraform.git
cd 2026-terraform

# 한글 폴더명이므로 glob 패턴으로 이동 (탭 자동완성 대신)
cd 05/2*/1*     # = 05/2과제/1모듈

# Terraform 실행
terraform init
terraform apply -auto-approve
# ⏱ EKS 생성 약 10~15분 소요

# Bastion에서 kubeconfig 설정
BASTION_IP=$(terraform output -raw bastion_eip 2>/dev/null || aws ec2 describe-instances --region ap-northeast-2 --filters "Name=tag:Name,Values=wsc-scaling-bastion" "Name=instance-state-name,Values=running" --query "Reservations[0].Instances[0].PublicIpAddress" --output text)
```

### 3모듈 - Container Logging (ap-northeast-1)

```bash
cd ~/2026-terraform
cd 05/2*/3*     # = 05/2과제/3모듈

terraform init
terraform apply -auto-approve
# ⏱ EKS 생성 약 10~15분 소요
```

---

## 후속 작업 (Bastion SSH 접속 후)

### 1모듈 후속 작업

```bash
# Bastion 접속 후 kubeconfig 설정
aws eks update-kubeconfig --region ap-northeast-2 --name wsc-scaling-cluster

# Namespace 생성
kubectl create namespace wsc-scaling

# Deployment 배포
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: wsc-scaling-deploy
  namespace: wsc-scaling
  labels:
    dedicated: scaling
spec:
  replicas: 2
  selector:
    matchLabels:
      app: wsc-scaling
  template:
    metadata:
      labels:
        app: wsc-scaling
        dedicated: scaling
    spec:
      containers:
      - name: busybox
        image: busybox:latest
        command: ["sleep", "infinity"]
        resources:
          requests:
            cpu: 250m
            memory: 256Mi
          limits:
            cpu: 500m
            memory: 512Mi
EOF

# KEDA 설치
helm repo add kedacore https://kedacore.github.io/charts
helm repo update
helm install keda kedacore/keda --namespace keda --create-namespace

# KEDA ScaledObject 배포
SQS_URL=$(aws sqs get-queue-url --queue-name wsc-scaling-sqs --query 'QueueUrl' --output text)
AWS_REGION="ap-northeast-2"

cat <<EOF | kubectl apply -f -
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
  triggers:
  - type: aws-sqs-queue
    metadata:
      queueURL: ${SQS_URL}
      queueLength: "5"
      awsRegion: ${AWS_REGION}
      identityOwner: operator
EOF

# Karpenter 설치 (helm)
# 사전에 Karpenter IAM, SQS interruption queue 등 구성 필요
helm repo add karpenter https://charts.karpenter.sh
helm repo update
helm install karpenter karpenter/karpenter --namespace karpenter --create-namespace \
  --set settings.clusterName=wsc-scaling-cluster \
  --set settings.interruptionQueue=wsc-scaling-cluster

# Karpenter NodePool
cat <<EOF | kubectl apply -f -
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: wsc-scaling-nodepool
spec:
  template:
    spec:
      requirements:
      - key: kubernetes.io/arch
        operator: In
        values: ["amd64"]
      - key: node.kubernetes.io/instance-type
        operator: In
        values: ["t3.medium"]
      nodeClassRef:
        group: eks.amazonaws.com
        kind: NodeClass
        name: default
  limits:
    cpu: "100"
    memory: 200Gi
  disruption:
    consolidationPolicy: WhenEmpty
    consolidateAfter: 30s
EOF
```

### 3모듈 후속 작업

```bash
# Bastion(EC2)에서 kubeconfig 설정
aws eks update-kubeconfig --region ap-northeast-1 --name wsc-logging-cluster

# Namespace 생성
kubectl create namespace wsc-logging

# Helm 설치
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Loki 설치 (SingleBinary, NLB)
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

cat <<EOF > loki-values.yaml
deploymentMode: SingleBinary
singleBinary:
  replicas: 1
loki:
  commonConfig:
    replication_factor: 1
  storage:
    type: filesystem
  schemaConfig:
    configs:
    - from: "2024-01-01"
      store: tsdb
      object_store: filesystem
      schema: v13
      index:
        prefix: loki_index_
        period: 24h
singleBinary:
  persistence:
    enabled: true
    size: 10Gi
gateway:
  enabled: false
read:
  replicas: 0
write:
  replicas: 0
backend:
  replicas: 0
service:
  type: LoadBalancer
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-type: "nlb"
  port: 3100
EOF

helm install loki grafana/loki -n wsc-logging -f loki-values.yaml

# Loki NLB DNS 확인 (FluentBit 설정에 사용)
LOKI_LB=$(kubectl get svc -n wsc-logging -l app.kubernetes.io/name=loki -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}')
echo "Loki NLB: $LOKI_LB"

# Grafana 설치 (NLB)
# 비번호를 NM 변수에 설정
NM="YOUR_NUMBER"

cat <<EOF > grafana-values.yaml
adminUser: wsc2026-admin-${NM}
adminPassword: admin${NM}!
service:
  type: LoadBalancer
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-type: "nlb"
datasources:
  datasources.yaml:
    apiVersion: 1
    datasources:
    - name: Loki
      type: loki
      url: http://loki.wsc-logging.svc:3100
      access: proxy
      isDefault: true
dashboardProviders:
  dashboardproviders.yaml:
    apiVersion: 1
    providers:
    - name: default
      folder: ''
      type: file
      options:
        path: /var/lib/grafana/dashboards/default
dashboards:
  default:
    wsc2026:
      json: |
        {
          "title": "WSC2026 Container Logs",
          "time": {"from": "now-1h", "to": "now"},
          "refresh": "5s",
          "panels": [
            {
              "title": "Any Log",
              "type": "logs",
              "gridPos": {"h":8,"w":24,"x":0,"y":0},
              "targets": [{"expr": "{namespace=\"wsc-app-log\"}", "refId": "A"}],
              "datasource": {"type":"loki","uid":"${DS_LOKI}"}
            },
            {
              "title": "INFO Log Count",
              "type": "timeseries",
              "gridPos": {"h":8,"w":8,"x":0,"y":8},
              "targets": [{"expr": "count_over_time({namespace=\"wsc-app-log\"} |= \"INFO\" [1m])", "refId": "A"}],
              "datasource": {"type":"loki","uid":"${DS_LOKI}"}
            },
            {
              "title": "ERROR Log Count",
              "type": "timeseries",
              "gridPos": {"h":8,"w":8,"x":8,"y":8},
              "targets": [{"expr": "count_over_time({namespace=\"wsc-app-log\"} |= \"ERROR\" [1m])", "refId": "A"}],
              "datasource": {"type":"loki","uid":"${DS_LOKI}"}
            },
            {
              "title": "WARNING Log Count",
              "type": "timeseries",
              "gridPos": {"h":8,"w":8,"x":16,"y":8},
              "targets": [{"expr": "count_over_time({namespace=\"wsc-app-log\"} |= \"WARNING\" [1m])", "refId": "A"}],
              "datasource": {"type":"loki","uid":"${DS_LOKI}"}
            }
          ]
        }
EOF

helm install grafana grafana/grafana -n wsc-logging -f grafana-values.yaml

# EC2의 FluentBit 설정 업데이트 (SSM으로 실행)
INSTANCE_ID=$(aws ec2 describe-instances --region ap-northeast-1 --filters "Name=tag:Name,Values=wsc-logging-app-bastion" --query "Reservations[0].Instances[0].InstanceId" --output text)

aws ssm send-command --region ap-northeast-1 \
  --instance-ids $INSTANCE_ID \
  --document-name "AWS-RunShellScript" \
  --parameters "commands=[
    \"sed -i 's/LOKI_NLB_DNS/${LOKI_LB}/' /etc/fluent-bit/fluent-bit.conf\",
    \"systemctl restart fluent-bit\"
  ]"
```

---

## 검증

```bash
# 1모듈 검증
kubectl get ns wsc-scaling
kubectl get deploy -n wsc-scaling
kubectl get scaledobject -n wsc-scaling

# 3모듈 검증
kubectl get pods -n wsc-logging
kubectl get svc -n wsc-logging
EC2_IP=$(aws ec2 describe-instances --region ap-northeast-1 --filters "Name=tag:Name,Values=wsc-logging-app-bastion" "Name=instance-state-name,Values=running" --query "Reservations[0].Instances[0].PublicIpAddress" --output text)
curl http://$EC2_IP:5000/health
curl http://$EC2_IP:5000/generate?count=10
```
