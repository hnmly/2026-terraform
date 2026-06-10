# 2026 전국기능경기대회 08 - 1과제: Solution Architecture

AWS 기반 클라우드 인프라를 구축하고, Book 애플리케이션을 ECS Fargate로 배포하여 CloudFront 단일 엔드포인트를 통해 정적 페이지와 API를 제공하는 Terraform 템플릿입니다.

## 아키텍처 개요

```
사용자 → CloudFront → S3 (정적 페이지: index.html, main.jpeg)
                    → ALB (X-Origin-Verify 헤더 검증) → ECS Fargate (book app) → DynamoDB (KMS 암호화)
```

## 디렉토리 구조

```
08/1과제/
├── provider.tf          # AWS Provider 설정
├── variables.tf         # 변수 정의
├── outputs.tf           # 출력값 정의
├── vpc.tf               # VPC, Subnet, IGW, NAT, Route Table, VPC Endpoint
├── sg.tf                # Security Groups
├── s3_cloudfront.tf     # S3 버킷, CloudFront Distribution, OAC
├── alb.tf               # ALB, Target Group, Listener Rules
├── iam.tf               # ECS Execution Role, Task Role
├── ecs.tf               # ECR, ECS Cluster, Task Definition, Service
├── dynamodb.tf          # DynamoDB Table, KMS Key
├── cloudwatch.tf        # Log Group, Metric Filters, Alarms
└── app/
    ├── Dockerfile       # book 바이너리용 Docker 이미지
    ├── book             # (배포파일) Go 바이너리
    ├── index.html       # (배포파일) 정적 페이지
    └── main.jpeg        # (배포파일) 배경 이미지
```

## 배포 방법

### 1. EC2 인스턴스 생성 (빌드 전용, AL2023)

CloudShell 또는 콘솔에서 Public Subnet에 EC2 생성 (t3.micro, AL2023 AMI).
이후 SSH 또는 SSM으로 접속.

### 2. EC2에서 Docker 설치 및 ECR 푸시

```bash
# Docker 설치
sudo dnf install -y docker
sudo systemctl start docker
sudo systemctl enable docker
sudo usermod -aG docker ec2-user
newgrp docker

# AWS CLI는 AL2023에 기본 포함

# 배포파일을 EC2로 전송 (CloudShell에서 S3 경유 또는 직접 업로드)
mkdir -p ~/app
# book, Dockerfile을 ~/app 에 배치

# Dockerfile 작성
cat << 'EOF' > ~/app/Dockerfile
FROM amazonlinux:2023
COPY book /app/book
RUN chmod +x /app/book
EXPOSE 8080
CMD ["/app/book"]
EOF

# ECR 로그인
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION=ap-northeast-2
aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com

# 이미지 빌드 & 푸시
cd ~/app
docker build -t skills-book-app .
docker tag skills-book-app:latest ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/skills-book-app:latest
docker push ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/skills-book-app:latest
```

### 3. Terraform 배포

```bash
# Terraform 설치 (EC2 또는 CloudShell)
sudo dnf install -y yum-utils
sudo yum-config-manager --add-repo https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo
sudo dnf install -y terraform

# 프로젝트 디렉토리로 이동
cd ~/08/1과제

# 초기화 및 배포
terraform init
terraform apply -var="bibunho=YOUR_BIBUNHO"
```

> ⚠️ **순서 주의**: ECR 리포지토리를 먼저 생성한 뒤 이미지를 푸시해야 합니다.
> 방법 1: `terraform apply -target=aws_ecr_repository.book` → 이미지 푸시 → `terraform apply`
> 방법 2: 전체 `terraform apply` 후 이미지 푸시 → `aws ecs update-service --force-new-deployment`

### 4. ECS 서비스 재배포 (이미지 푸시 후)

```bash
aws ecs update-service \
  --cluster skills-book-cluster \
  --service skills-book-service \
  --force-new-deployment \
  --region ap-northeast-2
```

### 5. S3 정적 파일 업로드

```bash
BIBUNHO=YOUR_BIBUNHO
aws s3 cp index.html s3://skills-book-static-2026-${BIBUNHO}/index.html --content-type "text/html"
aws s3 cp main.jpeg s3://skills-book-static-2026-${BIBUNHO}/main.jpeg --content-type "image/jpeg"
```

### 6. 검증

```bash
# CloudFront 도메인 확인
CF_DOMAIN=$(aws cloudfront list-distributions --query "DistributionList.Items[0].DomainName" --output text)

# 정적 페이지 접근
curl -I https://${CF_DOMAIN}/index.html

# ALB 직접 접근 차단 확인 (403)
ALB_DNS=$(aws elbv2 describe-load-balancers --region ap-northeast-2 --query "LoadBalancers[0].DNSName" --output text)
curl -s -o /dev/null -w "%{http_code}" http://${ALB_DNS}/health

# Book API 테스트
curl -X POST https://${CF_DOMAIN}/v1/book \
  -H "Content-Type: application/json" \
  -d '{"client_id":"test","username":"tester","email":"test@example.com","concert_name":"skills"}'
```

### 7. 빌드용 EC2 정리

채점 전 빌드용 EC2는 종료(terminate)합니다. 채점에 불필요한 리소스입니다.

## 주요 리소스명

| 리소스 | 이름 |
|--------|------|
| VPC | skills-book-vpc |
| S3 Bucket | skills-book-static-2026-{비번호} |
| CloudFront | skills-book-cloudfront |
| ALB | skills-book-alb |
| ECR | skills-book-ecr |
| ECS Cluster | skills-book-cluster |
| ECS Service | skills-book-service |
| Task Definition | skills-book-task |
| Container | skills-book-container |
| DynamoDB Table | skills-book-booking |
| KMS Alias | alias/skills-book-ddb |
| Log Group | /ecs/skills-book-app |
| 4xx Alarm | skills-book-4xx-alarm |
| 5xx Alarm | skills-book-5xx-alarm |
| Execution Role | skills-book-ecs-execution-role |
| Task Role | skills-book-ecs-task-role |

## 채점 기준 주요 포인트

- VPC DNS Hostname/Resolution 활성화, Public/Private Subnet 서로 다른 AZ
- DynamoDB Gateway VPC Endpoint 필수
- S3 Block Public Access 4개 모두 true, OAC 사용
- CloudFront Default → S3, /v1/* → ALB (POST 포함)
- ALB Default Rule 403, X-Origin-Verify 헤더 일치 시만 Forward
- ECS Fargate, Private Subnet, assign_public_ip = false
- DynamoDB KMS CMK 암호화 (alias/skills-book-ddb)
- Execution Role과 Task Role 분리
- CloudWatch Metric Filter: 4xx/5xx 분리, Alarm Treat Missing Data = notBreaching
