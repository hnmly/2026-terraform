# 2026 전국기능경기대회 클라우드컴퓨팅 제2과제 — Small Challenge (Terraform)

4개 모듈(NoSQL / CDN / Workflow / RDS Connection)을 **서로 다른 리전**에 구성하는 과제입니다.
각 모듈은 지정 리전에서만 동작하며, 모듈 간 리소스를 공유하지 않습니다.

> ℹ️ **참고** — 문제지 유의사항 13)에는 "Terraform/CDK 등 IaC 사용 불가, 콘솔/CLI로 직접 생성"이라고
> 되어 있습니다. 실제 경기에서는 콘솔/CLI로 구축해야 점수가 인정됩니다.
> 본 코드는 **학습/연습용 Terraform 재현**입니다. 채점 스크립트(`grade_all.sh`)의 항목 기준에 맞춰 작성했습니다.

## 모듈 / 리전 / 채점

| 모듈 | 리전 | 핵심 리소스 | 배점 |
|------|------|-------------|------|
| Module1 NoSQL | `ap-northeast-2` | DynamoDB `nosql-products` + GSI + Stream + 20건 + `~/result.json` | 7.5 |
| Module2 CDN | `us-east-1` | S3 `cdn-static-<비번호>` + OAC + CloudFront + Function | 7.5 |
| Module3 Workflow | `ap-southeast-1` | S3 + DynamoDB `workflow-output` + Lambda + Step Functions | 7.5 |
| Module4 RDS | `ap-northeast-3` | Aurora MySQL Serverless v2 + Data API + Secret + Lambda | 7.5 |
| **합계** | | **20항목 × 1.5점** | **30** |

## 파일 구성

| 파일 | 내용 |
|------|------|
| `versions.tf`        | Terraform/Provider 버전 (aws, archive, random, null) |
| `providers.tf`       | 4개 리전 provider (seoul/use1/sg/osaka) |
| `variables.tf`       | `team_id`(비번호) 변수, 계정 데이터 |
| `module1_nosql.tf`   | DynamoDB 테이블 + GSI + Stream + 20건 + result.json |
| `module2_cdn.tf`     | S3 + OAC + CloudFront + CloudFront Function + 버킷 정책 |
| `module3_workflow.tf`| S3 + DynamoDB + Lambda + Step Functions + 실행 |
| `module4_rds.tf`     | Aurora Serverless v2 + Secret + Lambda |
| `outputs.tf`         | 모듈별 주요 출력값 |
| `files/`             | 지급파일 (정적 웹, lambda 코드, data.csv, query.sh 등) |

## 사전 요구사항

- Terraform >= 1.5, AWS CLI v2 (자격증명 구성 완료)
- `python3`, `bash` (Module1 `result.json` 생성, Module3 실행 — CloudShell 기본 제공)
- 4개 리전(ap-northeast-2, us-east-1, ap-southeast-1, ap-northeast-3) 사용 가능 권한

## 실행 방법 (CloudShell / Linux 권장)

`team_id`(비번호)는 기본값이 없어 `apply` 시 입력 프롬프트가 뜹니다.

```bash
terraform init
terraform apply      # team_id(비번호) 입력 후 yes
# 또는 한 줄: terraform apply -var="team_id=007"
```

> Aurora Serverless v2 기동과 CloudFront 배포에는 각각 수 분이 소요됩니다.
> `terraform apply`는 Aurora 인스턴스가 Available 될 때까지 대기합니다.

### 모듈별 동작 확인

```bash
# Module1: 조회 결과 파일
cat ~/result.json

# Module2: 커스텀 헤더
CF=$(terraform output -raw m2_cloudfront_domain)
curl -sI "https://$CF/index.html?v=1" | grep -i X-Custom-Header   # x-custom-header: wsc2026

# Module3: 워크플로 결과 저장 확인
aws dynamodb scan --table-name workflow-output --region ap-southeast-1 --select COUNT

# Module4: Lambda 실행
aws lambda invoke --function-name rds-query-function --region ap-northeast-3 response.json
cat response.json
```

### 채점 스크립트

지급된 채점 스크립트로 점수를 확인할 수 있습니다.

```bash
bash grade_all.sh <비번호>
```

## 정리

```bash
terraform destroy    # team_id 입력 후 yes
```

> S3 버킷은 `force_destroy`, Secret은 `recovery_window_in_days=0`, RDS는 `skip_final_snapshot`으로
> 설정되어 있어 정리가 깔끔하게 진행됩니다.

## 구현 메모

- **Module1**: 데이터 20건은 `aws_dynamodb_table_item`으로 삽입합니다. `~/result.json`은 환경
  의존(aws/python3 PATH) 때문에 자동화하지 않고, apply 후 `bash files/nosql/query.sh electronics`로
  생성합니다(CloudShell 권장).
- **Module2**: CloudFront Function(`cloudfront-js-2.0`)을 viewer-response에 연결하여
  `X-Custom-Header: wsc2026`를 추가합니다. S3는 퍼블릭 차단 + OAC + 버킷 정책으로 직접 접근을 막습니다.
- **Module3**: Step Functions(STANDARD)가 Lambda를 호출하며, SFN 역할에는 `lambda:InvokeFunction`만
  부여합니다. 실행(start-execution)은 채점 스크립트가 직접 수행하므로 자동화에서 제외했습니다.
- **Module4**: ap-northeast-3에는 기본 VPC가 없으므로 Aurora용 전용 VPC/서브넷/DB Subnet Group을
  함께 생성합니다(Data API는 퍼블릭 HTTPS라 IGW/NAT 불필요). Aurora MySQL Serverless v2(0.5~4 ACU)에
  Data API를 활성화하고, Secret `rds/aurora/admin`을 참조하는 Lambda가 RDS Data API로 SQL을 실행합니다.
