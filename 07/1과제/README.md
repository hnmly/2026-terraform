# 2026 전국기능경기대회 08 - 1과제

CloudShell에서 Terraform 설치 후 `terraform apply` 한 번으로 전체 인프라 + 이미지 빌드/푸시까지 완료됩니다.

## 배포 (CloudShell에서 실행)

```bash
# 1. Terraform 설치
sudo dnf install -y yum-utils
sudo yum-config-manager --add-repo https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo
sudo dnf install -y terraform

# 2. 이 리포 클론
git clone https://github.com/hnmly/2026-terraform.git
cd 2026-terraform/08/1과제

# 3. 배포 파일 복사 (지급파일의 book 바이너리를 app/ 에 넣기)
# CloudShell Actions > Upload file 로 book 업로드
cp ~/book app/book

# 4. 실행 (비번호만 입력)
terraform init
terraform apply -var="bibunho=YOUR_BIBUNHO" -auto-approve
```

끝. CloudFront 배포 반영까지 3~5분 대기 후 검증.

## 검증

```bash
# CloudFront 정적페이지
curl -I https://$(terraform output -raw cloudfront_domain)/index.html

# ALB 직접 접근 차단 (403)
curl -s -o /dev/null -w "%{http_code}" http://$(terraform output -raw alb_dns)/health

# Book API
curl -X POST https://$(terraform output -raw cloudfront_domain)/v1/book \
  -H "Content-Type: application/json" \
  -d '{"client_id":"test","username":"tester","email":"t@t.com","concert_name":"skills"}'
```

## 구조

```
├── provider.tf          # AWS Provider
├── variables.tf         # bibunho, origin_verify_value
├── outputs.tf           # CloudFront domain, ALB DNS
├── vpc.tf               # VPC, Subnet, IGW, NAT, DynamoDB VPC Endpoint
├── sg.tf                # Security Group (all open)
├── alb.tf               # ALB, TG, Listener (default 403 + header forward)
├── s3_cloudfront.tf     # S3 + CloudFront OAC + /v1/* -> ALB
├── iam.tf               # Execution Role, Task Role (DynamoDB+KMS)
├── ecs.tf               # ECR + Docker build/push + ECS Cluster/Service
├── dynamodb.tf          # DynamoDB + KMS CMK
├── cloudwatch.tf        # Log Group, Metric Filters, Alarms
└── app/
    ├── Dockerfile
    ├── book             # 지급 바이너리
    ├── index.html
    └── main.jpeg
```

## 주요 리소스명

| 리소스 | 이름 |
|--------|------|
| VPC | skills-book-vpc |
| S3 | skills-book-static-2026-{비번호} |
| CloudFront | skills-book-cloudfront |
| ECR | skills-book-ecr (Name Tag) |
| ECS Cluster | skills-book-cluster |
| ECS Service | skills-book-service |
| Task Def | skills-book-task |
| Container | skills-book-container |
| DynamoDB | skills-book-booking |
| KMS | alias/skills-book-ddb |
| Log Group | /ecs/skills-book-app |
| Alarms | skills-book-4xx-alarm, skills-book-5xx-alarm |
| Execution Role | skills-book-ecs-execution-role |
| Task Role | skills-book-ecs-task-role |
