# 08 - 2과제: Small Challenges (모듈별 분리)

각 모듈을 독립적으로 `terraform init && terraform apply` 합니다.

## 사전 준비 (CloudShell)

```bash
# Terraform 설치
sudo dnf install -y yum-utils
sudo yum-config-manager --add-repo https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo
sudo dnf install -y terraform

# 소스 클론
git clone https://github.com/hnmly/2026-terraform.git
cd 2026-terraform/08/2과제
```

## 모듈1: DocumentDB (서울, ~10분)

```bash
cd module1
terraform init
terraform apply -var="docdb_password=Skills2026!" -auto-approve
cd ..
```

### apply 후 수동 작업

```bash
# EC2 인스턴스 ID 확인
INSTANCE_ID=$(aws ec2 describe-instances --region ap-northeast-2 \
  --filters Name=tag:Name,Values=skills-nosql-client-ec2 Name=instance-state-name,Values=running \
  --query "Reservations[0].Instances[0].InstanceId" --output text)

# SSM 접속
aws ssm start-session --target $INSTANCE_ID --region ap-northeast-2

# EC2 내부에서 앱 실행
export DOCDB_HOST=$(aws secretsmanager get-secret-value --secret-id skills-nosql-docdb-secret --region ap-northeast-2 --query SecretString --output text | python3 -c "import json,sys;print(json.load(sys.stdin)['host'])")
export DOCDB_USER=skillsadmin
export DOCDB_PASS=Skills2026!
export DOCDB_PORT=27017
export DOCDB_TLS=true
export DOCDB_CA_PATH=/opt/skills-nosql/global-bundle.pem

cd /opt/skills-nosql
nohup ./run_app.sh &
sleep 5
./run_seed.sh
```

## 모듈2: VPC Lattice (도쿄, ~3분)

```bash
cd module2
terraform init
terraform apply -auto-approve
cd ..
```

자동 완료. Client EC2 Public IP로 확인:
```bash
curl http://<Client-EC2-Public-IP>/health
```

## 모듈3: Cloud Event Handling (싱가포르, ~3분)

```bash
cd module3
terraform init
terraform apply -auto-approve
cd ..
```

자동 완료. `skills-ceh-protected-sg`의 Inbound 규칙이 0개인지 확인.

## 모듈4: EKS + KEDA + Karpenter (오레곤, ~15분)

```bash
cd module4
terraform init
terraform apply -auto-approve
cd ..
```

### apply 후 K8s 리소스 배포

```bash
# kubectl 설치
EKS_VER=$(aws eks describe-cluster --region us-west-2 --name skills-sqs-cluster --query 'cluster.version' --output text)
curl -LO "https://dl.k8s.io/release/v${EKS_VER}.0/bin/linux/amd64/kubectl"
chmod +x kubectl && sudo mv kubectl /usr/local/bin/

# Helm 설치
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# kubeconfig 설정
aws eks update-kubeconfig --region us-west-2 --name skills-sqs-cluster

# K8s 리소스 배포
chmod +x ../k8s-apply.sh
bash ../k8s-apply.sh
```

## 파일 구조

```
08/2과제/
├── module1/        # DocumentDB (ap-northeast-2)
│   ├── provider.tf
│   ├── variables.tf
│   └── module1.tf
├── module2/        # VPC Lattice (ap-northeast-1)
│   ├── provider.tf
│   └── module2.tf
├── module3/        # EventBridge+Lambda (ap-southeast-1)
│   ├── provider.tf
│   └── module3.tf
├── module4/        # EKS+SQS (us-west-2)
│   ├── provider.tf
│   └── module4.tf
├── app/            # 앱 소스코드
├── k8s-apply.sh    # 모듈4 K8s 배포 스크립트
└── README.md
```

## 소요시간 목안

| 모듈 | 리전 | 예상시간 | 자동/수동 |
|------|------|----------|-----------|
| 1 | 서울 | ~10분 | 수동: EC2에서 앱 실행 |
| 2 | 도쿄 | ~3분 | 자동 |
| 3 | 싱가포르 | ~3분 | 자동 |
| 4 | 오레곤 | ~15분 | 수동: k8s-apply.sh |


---

## 채점 방법 (CloudShell)

### 배점 (총 30점)

| 모듈 | 항목 | 배점 |
|------|------|------|
| 1 | DocumentDB based NoSQL Application | 7.5 |
| 2 | VPC Lattice | 7.5 |
| 3 | Cloud Event Handling | 7.5 |
| 4 | EKS + SQS + KEDA + Karpenter | 7.5 |

### 0. 사전 준비

```bash
aws --version
curl --version
jq --version

# kubectl 설치 (없는 경우)
EKS_VERSION=$(aws eks describe-cluster --region us-west-2 --name skills-sqs-cluster --query 'cluster.version' --output text)
KUBECTL_VERSION="v${EKS_VERSION}.0"
curl -L -o /tmp/kubectl "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
chmod +x /tmp/kubectl
export PATH="/tmp:$PATH"

# 채점 변수 선언
export NOSQL_CLIENT_EC2_PUBLIC_IP=$(aws ec2 describe-instances --region ap-northeast-2 --filters Name=tag:Name,Values=skills-nosql-client-ec2 Name=instance-state-name,Values=running --query "Reservations[0].Instances[0].PublicIpAddress" --output text)
export LATTICE_CLIENT_EC2_PUBLIC_IP=$(aws ec2 describe-instances --region ap-northeast-1 --filters Name=tag:Name,Values=skills-lattice-client-ec2 Name=instance-state-name,Values=running --query "Reservations[0].Instances[0].PublicIpAddress" --output text)
export SERVICE_NETWORK_ID=$(aws vpc-lattice list-service-networks --region ap-northeast-1 --query "items[?name=='skills-lattice-sn'].id | [0]" --output text)
export TARGET_GROUP_ID=$(aws vpc-lattice list-target-groups --region ap-northeast-1 --query "items[?name=='skills-lattice-order-tg'].id | [0]" --output text)
export SERVICE_ID=$(aws vpc-lattice list-services --region ap-northeast-1 --query "items[?name=='skills-lattice-order-service'].id | [0]" --output text)
export SERVICE_EC2_SECURITY_GROUP_ID=$(aws ec2 describe-instances --region ap-northeast-1 --filters Name=tag:Name,Values=skills-lattice-service-ec2 Name=instance-state-name,Values=running --query "Reservations[0].Instances[0].SecurityGroups[0].GroupId" --output text)
export QUEUE_URL=$(aws sqs get-queue-url --region us-west-2 --queue-name skills-sqs-queue --query QueueUrl --output text)
```

### 1. 모듈1 채점: DocumentDB (1.5점 x 5 = 7.5점)

```bash
# 1-1) DocumentDB Cluster/Instance/KMS 확인
aws docdb describe-db-clusters --region ap-northeast-2 --db-cluster-identifier skills-nosql-docdb-cluster --output table
aws docdb describe-db-instances --region ap-northeast-2 --db-instance-identifier skills-nosql-docdb-instance-1 --output table
aws kms describe-key --region ap-northeast-2 --key-id alias/skills-nosql-docdb --output table

# 1-2) Secret 및 Client EC2 확인
aws secretsmanager get-secret-value --region ap-northeast-2 --secret-id skills-nosql-docdb-secret --query SecretString --output text
aws ec2 describe-instances --region ap-northeast-2 --filters Name=tag:Name,Values=skills-nosql-client-ec2 Name=instance-state-name,Values=running --output table

# 1-3) Client App /health, /v1/admin/summary 확인
curl -s -w "\nhttp_code=%{http_code}\n" http://${NOSQL_CLIENT_EC2_PUBLIC_IP}:8080/health
curl -s -w "\nhttp_code=%{http_code}\n" http://${NOSQL_CLIENT_EC2_PUBLIC_IP}:8080/v1/admin/summary

# 1-4) Index/TTL 확인
curl -s -w "\nhttp_code=%{http_code}\n" http://${NOSQL_CLIENT_EC2_PUBLIC_IP}:8080/v1/admin/indexes

# 1-5) 조회 기능 검증
curl -s -w "\nhttp_code=%{http_code}\n" http://${NOSQL_CLIENT_EC2_PUBLIC_IP}:8080/v1/orders/O-1001
curl -s -w "\nhttp_code=%{http_code}\n" http://${NOSQL_CLIENT_EC2_PUBLIC_IP}:8080/v1/customers/C001/orders
curl -s -w "\nhttp_code=%{http_code}\n" "http://${NOSQL_CLIENT_EC2_PUBLIC_IP}:8080/v1/orders/pending?from=2026-06-01T00:00:00Z&to=2026-06-08T00:00:00Z"
curl -s -w "\nhttp_code=%{http_code}\n" "http://${NOSQL_CLIENT_EC2_PUBLIC_IP}:8080/v1/products/low-stock?warehouseId=W-A"
```

### 2. 모듈2 채점: VPC Lattice (1.5점 x 5 = 7.5점)

```bash
# 2-1) VPC 확인
aws ec2 describe-vpcs --region ap-northeast-1 --filters Name=tag:Name,Values=skills-lattice-client-vpc,skills-lattice-service-vpc --output table

# 2-2) EC2 상태 및 /health 확인
aws ec2 describe-instances --region ap-northeast-1 --filters Name=tag:Name,Values=skills-lattice-client-ec2,skills-lattice-service-ec2 Name=instance-state-name,Values=running --output table
curl -s -w "\nhttp_code=%{http_code}\n" http://${LATTICE_CLIENT_EC2_PUBLIC_IP}/health

# 2-3) Service Network/Service/Association 확인
aws vpc-lattice list-service-networks --region ap-northeast-1 --output table
aws vpc-lattice list-services --region ap-northeast-1 --output table
aws vpc-lattice list-service-network-vpc-associations --region ap-northeast-1 --service-network-identifier "$SERVICE_NETWORK_ID" --output table
aws vpc-lattice list-service-network-service-associations --region ap-northeast-1 --service-network-identifier "$SERVICE_NETWORK_ID" --output table

# 2-4) Target Group/Listener/SG 확인
aws vpc-lattice list-target-groups --region ap-northeast-1 --output table
aws vpc-lattice list-targets --region ap-northeast-1 --target-group-identifier "$TARGET_GROUP_ID" --output table
aws vpc-lattice list-listeners --region ap-northeast-1 --service-identifier "$SERVICE_ID" --output table
aws ec2 describe-security-groups --region ap-northeast-1 --group-ids "$SERVICE_EC2_SECURITY_GROUP_ID" --output json

# 2-5) End-to-End 검증 (order_id=1001, via=vpc-lattice 포함 확인)
curl -s -w "\nhttp_code=%{http_code}\n" "http://${LATTICE_CLIENT_EC2_PUBLIC_IP}/v1/client/orders?id=1001"
```

### 3. 모듈3 채점: Cloud Event Handling (1.5점 x 5 = 7.5점)

```bash
# 3-1) VPC/EC2/SG 존재 확인
aws ec2 describe-vpcs --region ap-southeast-1 --filters Name=tag:Name,Values=skills-ceh-vpc --output table
aws ec2 describe-instances --region ap-southeast-1 --filters Name=tag:Name,Values=skills-ceh-ec2 Name=instance-state-name,Values=running --output table
aws ec2 describe-security-groups --region ap-southeast-1 --filters Name=tag:Name,Values=skills-ceh-protected-sg --output table

# 3-2) Inbound 규칙 0개 확인
aws ec2 describe-security-groups --region ap-southeast-1 --filters Name=tag:Name,Values=skills-ceh-protected-sg --query "SecurityGroups[].IpPermissions" --output json

# 3-3) SNS Topic / Lambda 확인
aws sns list-topics --region ap-southeast-1 --output table
aws lambda get-function-configuration --region ap-southeast-1 --function-name skills-ceh-remediate-fn --output table

# 3-4) CloudTrail / EventBridge 확인
aws cloudtrail get-trail-status --region ap-southeast-1 --name skills-ceh-cloudtrail --output table
aws events describe-rule --region ap-southeast-1 --name skills-ceh-sg-change-rule --event-bus-name default --output json
aws events list-targets-by-rule --region ap-southeast-1 --rule skills-ceh-sg-change-rule --event-bus-name default --output table
aws lambda get-policy --region ap-southeast-1 --function-name skills-ceh-remediate-fn --query Policy --output text

# 3-5) 최종 기능 검증 (180초 이내 복구 확인)
export PROTECTED_SECURITY_GROUP_ID=$(aws ec2 describe-security-groups --region ap-southeast-1 --filters Name=tag:Name,Values=skills-ceh-protected-sg --query "SecurityGroups[0].GroupId" --output text)
aws ec2 authorize-security-group-ingress --region ap-southeast-1 --group-id "$PROTECTED_SECURITY_GROUP_ID" --protocol tcp --port 22 --cidr 0.0.0.0/0
jq -n --arg sg "$PROTECTED_SECURITY_GROUP_ID" '{detail:{eventName:"AuthorizeSecurityGroupIngress",requestParameters:{groupId:$sg}}}' > /tmp/skills-ceh-remediate-event.json
aws lambda invoke --region ap-southeast-1 --function-name skills-ceh-remediate-fn --cli-binary-format raw-in-base64-out --payload file:///tmp/skills-ceh-remediate-event.json /tmp/skills-ceh-remediate-output.json
aws ec2 describe-security-groups --region ap-southeast-1 --group-ids "$PROTECTED_SECURITY_GROUP_ID" --query "SecurityGroups[0].IpPermissions" --output json
aws logs describe-log-groups --region ap-southeast-1 --log-group-name-prefix /aws/lambda/skills-ceh-remediate-fn --output table
```

### 4. 모듈4 채점: EKS + SQS (1.25점 x 6 = 7.5점)

```bash
# 4-1) EKS Cluster / Fargate Profile / kubectl 접근
aws eks describe-cluster --region us-west-2 --name skills-sqs-cluster --output table
aws eks describe-fargate-profile --region us-west-2 --cluster-name skills-sqs-cluster --fargate-profile-name skills-sqs-fp-keda --output table
aws eks describe-fargate-profile --region us-west-2 --cluster-name skills-sqs-cluster --fargate-profile-name skills-sqs-fp-karpenter --output table
aws eks update-kubeconfig --region us-west-2 --name skills-sqs-cluster
kubectl get nodes -l eks.amazonaws.com/compute-type=fargate -o wide

# 4-2) SQS Queue / IRSA ServiceAccount 확인
aws sqs get-queue-url --region us-west-2 --queue-name skills-sqs-queue
aws sqs get-queue-attributes --region us-west-2 --queue-url "$QUEUE_URL" --attribute-names QueueArn VisibilityTimeout FifoQueue --output table
kubectl get serviceaccount keda-operator -n keda -o yaml
kubectl get serviceaccount karpenter -n karpenter -o yaml
kubectl get serviceaccount sqs-worker-sa -n skills-sqs -o yaml

# 4-3) KEDA/Karpenter Controller Running + Fargate Node
kubectl get deployment,pod -n keda -o wide
kubectl get deployment,pod -n karpenter -o wide

# 4-4) Worker Deployment / ScaledObject / TriggerAuthentication
kubectl get deployment sqs-worker -n skills-sqs -o yaml
kubectl get scaledobject sqs-worker-scaledobject -n skills-sqs -o yaml
kubectl get triggerauthentication sqs-worker-trigger-auth -n skills-sqs -o yaml

# 4-5) NodePool / EC2NodeClass / Worker Node 배치
kubectl get nodepool skills-sqs-nodepool -o yaml
kubectl get ec2nodeclass skills-sqs-nodeclass -o yaml
kubectl get nodes -l karpenter.sh/nodepool=skills-sqs-nodepool,skills-nodepool=event-worker -o wide
kubectl get pods -n skills-sqs -l app=sqs-worker -o wide

# 4-6) SQS Scale Out 검증 (180초 이내 Pod/Node 증가 확인)
for i in $(seq 1 12); do aws sqs send-message --region us-west-2 --queue-url "$QUEUE_URL" --message-body "judge-$i"; done
aws sqs get-queue-attributes --region us-west-2 --queue-url "$QUEUE_URL" --attribute-names ApproximateNumberOfMessages ApproximateNumberOfMessagesNotVisible --output table
kubectl get pods -n skills-sqs -l app=sqs-worker -o wide
kubectl get nodes -l karpenter.sh/nodepool=skills-sqs-nodepool,skills-nodepool=event-worker -o wide
```
