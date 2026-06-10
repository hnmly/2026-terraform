# 2026 전국기능경기대회 08 - 2과제: Small Challenges

4개 모듈을 단일 `terraform apply`로 전체 인프라 생성. 모듈4 K8s 리소스는 별도 스크립트.

## 배포 (CloudShell)

```bash
# 1. Terraform + Helm + kubectl 설치
sudo dnf install -y yum-utils
sudo yum-config-manager --add-repo https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo
sudo dnf install -y terraform

# Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# kubectl (EKS 생성 후)
# EKS_VERSION=$(aws eks describe-cluster --region us-west-2 --name skills-sqs-cluster --query 'cluster.version' --output text)
# curl -LO "https://dl.k8s.io/release/v${EKS_VERSION}.0/bin/linux/amd64/kubectl" && chmod +x kubectl && sudo mv kubectl /usr/local/bin/

# 2. 클론 및 실행
git clone https://github.com/hnmly/2026-terraform.git
cd 2026-terraform/08/2과제

# 3. Terraform apply (4개 모듈 동시 생성)
terraform init
terraform apply -var="docdb_password=Skills2026!" -auto-approve

# 4. 모듈4 K8s 리소스 배포 (EKS 생성 후)
chmod +x k8s-apply.sh
./k8s-apply.sh
```

## 모듈별 수동 작업

### 모듈1: DocumentDB 앱 설치 (EC2 SSM 접속 후)

```bash
# EC2에 SSM 접속 후 앱 파일 전송 및 실행
cd /tmp
# app/module1/* 파일을 EC2에 전송 (S3 경유 또는 scp)
chmod +x install_client_app.sh run_app.sh run_seed.sh
./install_client_app.sh

# 환경변수 설정
export DOCDB_HOST=$(aws secretsmanager get-secret-value --secret-id skills-nosql-docdb-secret --region ap-northeast-2 --query SecretString --output text | python3 -c "import json,sys;print(json.load(sys.stdin)['host'])")
export DOCDB_USER=skillsadmin
export DOCDB_PASS=Skills2026!
export DOCDB_PORT=27017
export DOCDB_TLS=true
export DOCDB_CA_PATH=/opt/skills-nosql/global-bundle.pem

./run_seed.sh
./run_app.sh &
```

## 구조

```
08/2과제/
├── provider.tf      # 4개 리전 provider
├── variables.tf     # docdb_password
├── module1.tf       # DocumentDB (서울)
├── module2.tf       # VPC Lattice (도쿄)
├── module3.tf       # Cloud Event Handling (싱가포르)
├── module4.tf       # EKS + SQS (오레곤)
├── k8s-apply.sh     # 모듈4 K8s 리소스 배포 스크립트
└── app/
    ├── module1/     # DocumentDB 앱 파일
    ├── module2/     # VPC Lattice client/service 앱
    ├── module3/     # Lambda 소스
    └── module4/     # Worker Dockerfile, worker.py
```

## 리전별 리소스

| 모듈 | 리전 | 주요 리소스 |
|------|------|-------------|
| 1 | ap-northeast-2 (서울) | DocumentDB, EC2 Client, Secrets Manager |
| 2 | ap-northeast-1 (도쿄) | VPC Lattice, Client/Service EC2 |
| 3 | ap-southeast-1 (싱가포르) | EventBridge, Lambda, CloudTrail, SNS |
| 4 | us-west-2 (오레곤) | EKS, SQS, KEDA, Karpenter |
