# 09 - 2과제: Small Challenge (Terraform)

4개 모듈을 단일 `terraform apply`로 배포합니다. **반드시 CloudShell에서 실행하세요** (Module1 `result.json` 채점 때문).

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
cd 2026-terraform/09/2과제
```

### 3. 배포

```bash
terraform init
terraform apply -var="team_id=<비번호>" -auto-approve
```

> Aurora Serverless v2 기동 ~10분, CloudFront 배포 ~3분 소요.

### 4. Module1 result.json 생성 (채점 필수)

```bash
bash files/nosql/query.sh electronics
cat ~/result.json
```

### 5. 동작 확인

```bash
# Module2: CloudFront 커스텀 헤더
CF=$(terraform output -raw m2_cloudfront_domain)
curl -sI "https://$CF/index.html?v=1" | grep -i X-Custom-Header

# Module3: 워크플로 데이터 저장 확인
aws dynamodb scan --table-name workflow-output --region ap-southeast-1 --select COUNT

# Module4: Lambda 실행
aws lambda invoke --function-name rds-query-function --region ap-northeast-3 response.json
cat response.json
```

### 6. 채점

```bash
bash grade_module1.sh <비번호>
bash grade_module2.sh <비번호>
bash grade_module3.sh <비번호>
bash grade_module4.sh
```

### 7. 정리

```bash
terraform destroy -var="team_id=<비번호>" -auto-approve
```

## 모듈 구성

| 모듈 | 리전 | 핵심 리소스 |
|------|------|-------------|
| 1 NoSQL | ap-northeast-2 | DynamoDB `nosql-products` + GSI + 20건 + `~/result.json` |
| 2 CDN | us-east-1 | S3 `cdn-static-<비번호>` + OAC + CloudFront + Function(X-Custom-Header) |
| 3 Workflow | ap-southeast-1 | S3 + Lambda + DynamoDB `workflow-output` + Step Functions |
| 4 RDS | ap-northeast-3 | Aurora MySQL Serverless v2 + Data API + Secret + Lambda |
