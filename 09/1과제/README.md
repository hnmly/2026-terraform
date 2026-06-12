# 09 - 1과제: Solution Architecture (Terraform)

CloudShell에서 단일 `terraform apply`로 전체 인프라를 배포합니다.

## CloudShell 실행 방법

### 1. Terraform 설치

```bash
sudo dnf install -y yum-utils
sudo yum-config-manager --add-repo https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo
sudo dnf install -y terraform
```

### 2. 클론 & 이동

```bash
git clone https://github.com/hnmly/2026-terraform.git
cd 2026-terraform/09/1과제
```

### 3. 배포

```bash
terraform init
terraform apply -var="player_id=<선수ID>" -auto-approve
```

> CloudFront 배포 완료까지 최대 3분 소요.

### 4. 동작 확인

```bash
CF=$(terraform output -raw cloudfront_domain_name)

# 정적 페이지
curl -s -o /dev/null -w "%{http_code}" "https://$CF/"

# 헬스 체크
curl -s "https://$CF/health"

# 예약 생성
curl -s -X POST "https://$CF/v1/book" \
  -H "Content-Type: application/json" \
  -d '{"client_id":"C001","username":"Alice","email":"kim@example.com","concert_name":"Seoul2026"}'
```

### 5. 정리

```bash
terraform destroy -var="player_id=<선수ID>" -auto-approve
```

## 아키텍처

```
사용자 → CloudFront → S3 (정적 파일, OAC)
                    → ALB → ECS Fargate (book:8080) → DynamoDB
                                                    → CloudWatch Logs (/skillskorea/ecs/app)
```

## 리소스 요약

| 리소스 | 이름 |
|--------|------|
| VPC | `<선수ID>-vpc` (10.0.0.0/16) |
| Public Subnet | 2개 (ap-northeast-2a, 2c) |
| S3 | `<선수ID>-static-site` |
| CloudFront | S3 + ALB 오리진 |
| ECR | `<선수ID>-book-ecr` |
| ECS | `<선수ID>-book-cluster` / `<선수ID>-book-service` |
| ALB | `<선수ID>-book-alb` |
| DynamoDB | `<선수ID>-booking-table` |
| CloudWatch | `/skillskorea/ecs/app` |
