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

## 사전 준비

1. AWS CLI 설정 완료 (ap-northeast-2)
2. Terraform 설치
3. Docker 설치
4. 배포 파일(`book`, `index.html`, `main.jpeg`)을 `app/` 디렉토리에 복사

## 배포 방법

### 1. 배포 파일 복사

```bash
# app 디렉토리에 지급 파일 복사
cp /path/to/book ./app/
cp /path/to/index.html ./app/
cp /path/to/main.jpeg ./app/
```

### 2. Terraform 배포

```bash
# 초기화
terraform init

# 변수 설정 및 배포 (비번호를 본인 비번호로 변경)
terraform apply -var="bibunho=YOUR_BIBUNHO"
```

### 3. Docker 이미지 빌드 & ECR Push

```bash
# ECR 로그인
aws ecr get-login-password --region ap-northeast-2 | docker login --username AWS --password-stdin $(terraform output -raw ecr_repository_url | cut -d/ -f1)

# 이미지 빌드 (amd64)
cd app
docker build --platform linux/amd64 -t skills-book-app .

# 태그 및 푸시
docker tag skills-book-app:latest $(terraform output -raw ecr_repository_url):latest
docker push $(terraform output -raw ecr_repository_url):latest
cd ..
```

### 4. ECS Service 업데이트 (이미지 반영)

```bash
aws ecs update-service --cluster skills-book-cluster --service skills-book-service --force-new-deployment --region ap-northeast-2
```

### 5. 검증

```bash
# CloudFront 도메인으로 정적 페이지 접근
curl -I https://$(terraform output -raw cloudfront_domain_name)/index.html

# ALB 직접 접근 차단 확인 (403 반환)
curl -s -o /dev/null -w "%{http_code}" http://$(terraform output -raw alb_dns_name)/health

# Book API 테스트
curl -X POST https://$(terraform output -raw cloudfront_domain_name)/v1/book \
  -H "Content-Type: application/json" \
  -d '{"client_id":"test","username":"tester","email":"test@example.com","concert_name":"skills"}'
```

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
