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

./run_seed.sh
nohup ./run_app.sh &
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
chmod +x k8s-apply.sh
./k8s-apply.sh
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
