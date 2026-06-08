# 2026 전국기능경기대회 클라우드컴퓨팅 1과제 — 콘서트 예약 서비스 (Terraform)

지급된 정적 웹 파일(`index.html`, `main.jpeg`)과 컨테이너 실행 파일(`book`)을 사용하여
AWS 상에 콘서트 예약 서비스를 구축하는 **학습/참고용 Terraform** 구성입니다.

> ⚠️ **중요 — 실제 시험 감점 주의**
> 1과제 채점 스크립트(`grade_task1.sh`)의 **8-2 항목**에는 다음 경고가 있습니다.
> `※ IaC(Terraform, CDK 등) 사용 확인 시 0점 처리됩니다.`
> 또한 문제지 "사용 가능 Software Stack"에 Terraform은 포함되어 있지 않습니다
> (AWS Console / AWS CLI v2 / Docker만 명시).
> 따라서 **실제 경기에서는 콘솔 또는 CLI로 직접 구축**해야 하며, 이 Terraform 코드는
> 아키텍처 이해 및 연습 목적의 참고 자료로만 사용하시기 바랍니다.

---

## 아키텍처

```
                 ┌────────────────────────── CloudFront ──────────────────────────┐
 사용자 ──HTTPS──▶  /            , /*.html, /*.jpeg  ──▶  S3 (OAC, 퍼블릭 차단)      │
                 │  /health, /v1/*                   ──▶  ALB(HTTP:80)             │
                 └───────────────────────────────────────────┬────────────────────┘
                                                              ▼
                                       Target Group(HTTP:8080, ip) ──▶ ECS Fargate Task
                                                                         (book, 8080)
                                                                         │
                                          awslogs ──▶ CloudWatch Logs (/skillskorea/ecs/app)
                                                                         │
                                                                         ▼
                                                              DynamoDB (booking-table)
```

- **VPC** `10.0.0.0/16` + Public Subnet 2개(`ap-northeast-2a`, `ap-northeast-2c`) + IGW + Public Route Table
- **S3** `<id>-static-site` : Block Public Access 전면 차단, CloudFront **OAC**로만 접근
- **CloudFront** : S3(기본 경로) + ALB(`/v1/*`, `/health`) 2개 오리진, `DefaultRootObject=index.html`
- **ECR** `<id>-book-ecr` : `book` 바이너리를 Linux/AMD64 이미지로 빌드 후 `latest` push
- **ECS Fargate** : Cluster/Service/TaskDefinition (CPU 256 / Memory 512, 컨테이너 포트 8080)
- **ALB** `<id>-book-alb` : internet-facing, Listener HTTP:80, TG HTTP:8080(ip), 헬스체크 `/health`
- **DynamoDB** `<id>-booking-table` : PK `client_id`(S), On-demand(PAY_PER_REQUEST)
- **CloudWatch Logs** : `/skillskorea/ecs/app`, awslogs 드라이버, 스트림 접두어 `ecs`

## 파일 구성

| 파일 | 내용 |
|------|------|
| `versions.tf`        | Terraform/Provider 버전, AWS provider |
| `variables.tf`       | 입력 변수 (`player_id` 등) |
| `locals.tf`          | 공통 이름/계정 정보 |
| `network.tf`         | VPC, Subnet, IGW, Route Table |
| `security_groups.tf` | ALB SG, ECS SG |
| `s3.tf`              | S3 버킷, 정적 파일 업로드, 버킷 정책 |
| `cloudfront.tf`      | CloudFront Distribution, OAC |
| `ecr.tf`             | ECR Repository + Docker 빌드/푸시 자동화 |
| `app/Dockerfile`     | `book` 컨테이너 이미지 정의 |
| `ecs.tf`             | CloudWatch Logs, ECS Cluster/TaskDef/Service |
| `alb.tf`             | ALB, Target Group, Listener |
| `dynamodb.tf`        | DynamoDB 테이블 |
| `iam.tf`             | Task Execution Role, Task Role(DynamoDB 권한) |
| `outputs.tf`         | CloudFront 도메인 등 출력값 |

## 사전 요구사항

- Terraform >= 1.5
- AWS CLI v2 (자격증명 구성 완료, `ap-northeast-2`)
- Docker (buildx 포함) — ECR 이미지 빌드/푸시에 사용

## 배포 방법

```bash
# 1) 변수 파일 준비
cp terraform.tfvars.example terraform.tfvars
# terraform.tfvars 의 player_id 를 본인 선수ID로 수정 (소문자/숫자/하이픈)

# 2) 초기화
terraform init

# 3) 검토 및 적용
terraform plan
terraform apply
```

`terraform apply` 시 다음 순서로 처리됩니다.
1. 네트워크/보안그룹/DynamoDB/IAM/ECR 생성
2. `null_resource.docker_build_push` 가 `book` 이미지를 빌드해 ECR에 `latest`로 push
3. ECS TaskDefinition/Service, ALB, S3, CloudFront 생성

> CloudFront 배포 완료(`Deployed`)까지 수 분 소요될 수 있습니다.

### Docker 빌드/푸시 (수동, Linux/macOS)

`ecr.tf` 의 `local-exec` 는 Windows PowerShell 기준입니다. Linux/macOS에서 수동 실행 시:

```bash
ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
REGION=ap-northeast-2
REPO=<player_id>-book-ecr
aws ecr get-login-password --region $REGION \
  | docker login --username AWS --password-stdin $ACCOUNT.dkr.ecr.$REGION.amazonaws.com
docker buildx build --platform linux/amd64 \
  -t $ACCOUNT.dkr.ecr.$REGION.amazonaws.com/$REPO:latest --push ./app
```

## 동작 확인

```bash
CF=$(terraform output -raw cloudfront_domain_name)

curl -i https://$CF/                 # 정적 페이지 (200)
curl -i https://$CF/health           # {"status":"OK","version":"1.0.1"} (200)
curl -i -X POST https://$CF/v1/book \
  -H "Content-Type: application/json" \
  -d '{"client_id":"C001","username":"Alice","email":"kim@example.com","concert_name":"Seoul2026"}'
# => {"booking_id":"..."} (200), DynamoDB에 6개 속성 저장
```

## 정리

```bash
terraform destroy
```

> S3 버킷과 ECR 리포지토리는 `force_destroy`/`force_delete`로 설정되어 객체/이미지가 있어도 삭제됩니다.
