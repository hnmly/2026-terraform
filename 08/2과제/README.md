# 08 - 2과제: Small Challenges

단일 `terraform apply`로 4개 모듈 인프라 전체 생성.

---

## ⚡ 빠른 배포 (CloudShell 복붙)

```bash
# Terraform 설치
sudo dnf install -y yum-utils && sudo yum-config-manager --add-repo https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo && sudo dnf install -y terraform

# 클론
git clone https://github.com/hnmly/2026-terraform.git && cd 2026-terraform/08/2과제

# 전체 인프라 생성 (4개 리전 동시)
terraform init
terraform apply -var="docdb_password=Skills2026!" -auto-approve
```

⏱ 소요시간: DocumentDB ~10분, EKS ~15분 (가장 오래 걸림)

---

## 📋 terraform apply 이후 수동 작업

### 모듈1: DocumentDB 앱 실행

EC2에 SSM 접속 → 앱 파일 업로드 → seed + run

```bash
# CloudShell에서 앱 파일을 S3로 업로드
aws s3 cp app/module1/ s3://임시버킷/module1/ --recursive --region ap-northeast-2

# EC2 SSM 접속
aws ssm start-session --target <instance-id> --region ap-northeast-2

# EC2 안에서
aws s3 cp s3://임시버킷/module1/ /tmp/ --recursive
cd /tmp && chmod +x install_client_app.sh run_app.sh run_seed.sh
./install_client_app.sh

# 환경변수
export DOCDB_HOST=$(aws secretsmanager get-secret-value --secret-id skills-nosql-docdb-secret --region ap-northeast-2 --query SecretString --output text | python3 -c "import json,sys;print(json.load(sys.stdin)['host'])")
export DOCDB_USER=skillsadmin
export DOCDB_PASS=Skills2026!
export DOCDB_PORT=27017
export DOCDB_TLS=true
export DOCDB_CA_PATH=/opt/skills-nosql/global-bundle.pem

./run_seed.sh    # 데이터 적재
nohup ./run_app.sh &  # 앱 실행 (8080 포트)
```

### 모듈2: VPC Lattice

Terraform이 전부 처리. EC2 user_data로 앱 자동 실행됨.  
Client EC2 Public IP로 `curl http://<IP>/health` 확인.

### 모듈3: Cloud Event Handling

Terraform이 전부 처리. Lambda + EventBridge + CloudTrail 자동 구성.  
`skills-ceh-protected-sg`의 Inbound 규칙이 0개인지만 확인.

### 모듈4: EKS + KEDA + Karpenter

EKS 클러스터 생성 완료 후 K8s 리소스 배포:

```bash
# Helm + kubectl 설치
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
EKS_VER=$(aws eks describe-cluster --region us-west-2 --name skills-sqs-cluster --query 'cluster.version' --output text)
curl -LO "https://dl.k8s.io/release/v${EKS_VER}.0/bin/linux/amd64/kubectl" && chmod +x kubectl && sudo mv kubectl /usr/local/bin/

# K8s 리소스 전부 배포 (KEDA, Karpenter, Worker, ScaledObject, NodePool)
chmod +x k8s-apply.sh
./k8s-apply.sh
```

---

## 🗂 파일 구조

```
08/2과제/
├── provider.tf       # 서울/도쿄/싱가포르/오레곤 4개 provider
├── variables.tf      # docdb_password
├── module1.tf        # 모듈1: DocumentDB (ap-northeast-2)
├── module2.tf        # 모듈2: VPC Lattice (ap-northeast-1)
├── module3.tf        # 모듈3: EventBridge+Lambda (ap-southeast-1)
├── module4.tf        # 모듈4: EKS+SQS (us-west-2)
├── k8s-apply.sh      # 모듈4 K8s 배포 스크립트
└── app/
    ├── module1/      # DocumentDB 앱 (Python)
    ├── module2/      # VPC Lattice client/service (Python)
    ├── module3/      # Lambda 함수 (Python)
    └── module4/      # SQS Worker (Python + Dockerfile)
```

---

## 🎯 모듈별 요약

| 모듈 | 리전 | 핵심 | 자동/수동 |
|------|------|------|-----------|
| 1 | 서울 | DocumentDB + Client EC2 + Secrets | **수동**: EC2에서 앱 실행 |
| 2 | 도쿄 | VPC Lattice + Client/Service EC2 | **자동**: user_data로 완료 |
| 3 | 싱가포르 | EventBridge → Lambda → SG 복구 | **자동**: terraform 완료 |
| 4 | 오레곤 | EKS + SQS + KEDA + Karpenter | **수동**: k8s-apply.sh 실행 |
