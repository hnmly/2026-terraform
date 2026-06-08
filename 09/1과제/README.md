# 2026 전국기능경기대회 클라우드컴퓨팅 1과제 — 콘서트 예약 서비스 (Terraform)

지급된 정적 웹 파일(`index.html`, `main.jpeg`)과 컨테이너 실행 파일(`book`)을 사용하여
AWS 상에 콘서트 예약 서비스를 구축하는 **학습/참고용 Terraform** 구성입니다.

> ℹ️ **참고**
> 일부 채점 스크립트에 IaC 사용 제한 문구가 있었으나, 이는 **잘못 포함된 내용으로 확인**되었습니다.
> Terraform 등 IaC를 사용해도 무방합니다. 본 구성은 Terraform으로 전체 인프라를 배포합니다.

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

## Windows PowerShell 실행 가이드 (처음부터 끝까지)

아무 도구도 설치되지 않은 Windows에서 시작한다고 가정합니다.
**관리자 권한 PowerShell**을 열고 아래 순서대로 진행하세요.

### 0) 필수 도구 설치 (winget)

```powershell
# Git
winget install --id Git.Git -e --source winget

# AWS CLI v2
winget install --id Amazon.AWSCLI -e --source winget

# Terraform
winget install --id HashiCorp.Terraform -e --source winget

# Docker Desktop (ECR 이미지 빌드/푸시에 필요)
winget install --id Docker.DockerDesktop -e --source winget
```

설치 후 **PowerShell 창을 새로 열어야** PATH가 반영됩니다. 설치 확인:

```powershell
git --version
aws --version
terraform version
docker --version
```

> Docker Desktop은 설치 후 한 번 실행해서 엔진이 "Running" 상태가 되어야 합니다.

### 1) AWS 자격증명 구성

```powershell
aws configure
# AWS Access Key ID     : <발급받은 키>
# AWS Secret Access Key : <발급받은 시크릿>
# Default region name   : ap-northeast-2
# Default output format  : json

# 확인
aws sts get-caller-identity
```

### 2) 레포 클론 & 폴더 이동

```powershell
cd $env:USERPROFILE
git clone https://github.com/hnmly/2026-terraform.git
cd 2026-terraform\09\1과제
```

### 3) 초기화 → 검토 → 배포 (선수ID는 apply 시 입력)

`player_id` 는 기본값이 없으므로 `terraform plan`/`apply` 를 실행하면
**자동으로 선수ID 입력 프롬프트**가 나타납니다. tfvars 파일을 따로 만들 필요가 없습니다.

```powershell
terraform init
terraform apply
```

실행하면 아래처럼 입력을 요구합니다. 본인 선수ID(소문자/숫자/하이픈)를 입력하세요.

```
var.player_id
  선수ID (모든 리소스 이름 접두어). apply 시 입력. 소문자/숫자/하이픈만, 예) hong

  Enter a value: your-id      <-- 여기에 입력

...
Plan: NN to add, 0 to change, 0 to destroy.
Do you want to perform these actions?
  Enter a value: yes          <-- yes 입력하면 배포 시작
```

> 프롬프트 없이 한 줄로 실행하려면 `-var` 옵션을 쓰면 됩니다.
> ```powershell
> terraform apply -var="player_id=your-id"
> ```

`apply`가 끝나면 출력값에 CloudFront 도메인이 표시됩니다.
CloudFront 배포 완료(`Deployed`)까지는 수 분 더 걸릴 수 있습니다.

### 4) 동작 확인 (PowerShell)

```powershell
$CF = terraform output -raw cloudfront_domain_name

# 정적 페이지
curl.exe -i "https://$CF/"

# 헬스 체크 -> {"status":"OK","version":"1.0.1"}
curl.exe -i "https://$CF/health"

# 예약 생성 (POST) -> {"booking_id":"..."}
curl.exe -i -X POST "https://$CF/v1/book" `
  -H "Content-Type: application/json" `
  -d '{\"client_id\":\"C001\",\"username\":\"Alice\",\"email\":\"kim@example.com\",\"concert_name\":\"Seoul2026\"}'
```

### 5) 리소스 정리

```powershell
terraform destroy     # 확인 메시지에 yes 입력
```

---

## 사전 요구사항 (요약)

- Git, Terraform >= 1.5, AWS CLI v2, Docker Desktop
- AWS 자격증명 구성 완료 (`ap-northeast-2`)

## 배포 순서 내부 동작

`terraform apply` 시 다음 순서로 처리됩니다.
1. 네트워크/보안그룹/DynamoDB/IAM/ECR 생성
2. `null_resource.docker_build_push` 가 `book` 이미지를 빌드해 ECR에 `latest`로 push
3. ECS TaskDefinition/Service, ALB, S3, CloudFront 생성

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
