# 2026 전국기능경기대회 클라우드컴퓨팅 제1과제 (05) — EKS 기반 Solution Architecture

ZTNA/MSA 컨셉의 콘서트 예약 REST API를 **EKS 기반**으로 구축하는 과제입니다.
AWS 인프라는 **Terraform**, 클러스터 내부 리소스는 **Kubernetes 매니페스트/Helm**으로 구성합니다.

> ℹ️ 문제 유의사항상 실제 경기에서는 콘솔/CLI 구축이 요구될 수 있으나, 본 레포는
> **학습/연습용 Terraform + K8s 재현**입니다. 채점 스크립트(`mark.sh`)의 항목 기준에 맞춰 작성했습니다.

## 디렉터리 구조

```
05/1과제/
├── terraform/         # AWS 인프라 (VPC/KMS/Bastion/S3/ECR/DynamoDB/EKS/Lambda/CloudFront/WAF)
│   ├── *.tf
│   ├── policies/alb-controller-policy.json
│   └── lambda/lambda_function.py   # GET /v1/book
├── docker/            # book 컨테이너 (Dockerfile + book + static/)
├── k8s/               # 네임스페이스/앱/스토리지/CoreDNS/fluent-bit/monitoring
│   └── helm-values/   # prometheus/grafana values + 대시보드
└── scripts/           # build-and-push.sh, deploy-k8s.sh
```

## 아키텍처 요약

- **VPC** `10.0.0.0/16` — public/private/workload × 2AZ (총 6 서브넷). workload RT는 라우트 없음(인터넷 격리) → **Interface VPC Endpoint**로 AWS 접근
- **Bastion** (public, EIP, SSH 패스워드 `Skill53##`, Admin) — EKS는 Private endpoint이므로 kubectl은 여기서 실행
- **EKS** `wsc-eks-cluster` v1.35 (private-only, KMS secret 암호화, 컨트롤플레인 로깅) — workload 서브넷, 3개 Managed NodeGroup(app/addon/monitoring, t3.medium, EBS KMS, label `type=`)
- **데이터/레지스트리**: DynamoDB `wsc-table`(CMK), S3 `wsc-static-<ACCOUNT_ID>`(SSE-KMS), ECR `wsc-repo`(KMS, scanOnPush, IMMUTABLE)
- **앱**: `wsc` ns Deployment `wsc-deploy`/컨테이너 `wsc-cnt`, ConfigMap `wsc-config`, IRSA `wsc-sa`(노드 IAM 미사용)
- **LB**: 내부 ALB `wsc-app-lb`(CloudFront만 허용, /health→403, 미정의→404), 공개 ALB `wsc-addon-lb`(/grafana,/prometheus)
- **CloudFront** `wsc-cdn`(S3+ALB origin, IPv6 off, HTTP→HTTPS) + **WAF** `wsc-waf`(POST body admin/sysop 차단)
- **Lambda** `wsc-get-table-function`(private subnet, GET /v1/book)
- **관측**: Fluent Bit→CloudWatch `/wsc/pod/log`(KMS, /health 제외), Prometheus+Grafana(`wsc-eks-dashboard` 6패널)

## 배포 전략 (중요)

EKS가 **Private 전용 엔드포인트**라 클러스터 작업은 VPC 내부에서만 가능합니다.
따라서 **2단계**로 나눠 실행합니다.

| 단계 | 실행 위치 | 대상 |
|------|-----------|------|
| 1단계 | **로컬 PC** | VPC(네트워크 전체) + Bastion (+ 의존 IAM/SG/IGW/RT) |
| 2단계 | **Bastion** | 나머지 전부 — KMS/S3/ECR/DynamoDB/EKS/노드/Lambda/WAF/CloudFront + 이미지 빌드·푸시 + K8s 배포 |

> 1단계로 Bastion 접속 경로를 먼저 열고, EKS 등 클러스터 연계 작업은 private 엔드포인트에 닿는
> **Bastion에서** 수행합니다. Bastion에는 Admin 권한이 있어 거기서 나머지 `terraform apply`가 가능합니다.

### 0) 사전: 로컬에 Terraform, AWS CLI v2

### 1단계 — 로컬 PC: VPC + Bastion 만 생성

```bash
cd terraform
terraform init

# -target 의존성으로 VPC/서브넷/IGW/공용RT/SG/IAM + Bastion 이 함께 생성됨
terraform apply -target "aws_route.public_igw" -target "aws_route_table_association.public" -target "aws_eip.bastion" -target "aws_instance.bastion"

terraform output bastion_public_ip     # Bastion 공인 IP
```

### 2단계 — Bastion: 나머지 전부

Bastion 접속 (SSH 패스워드 `Skill53##`):

```bash
ssh ec2-user@<BASTION_IP>
```

Bastion 안에서:

```bash
# 도구 준비 (Bastion에는 docker 미설치)
sudo dnf install -y docker git && sudo systemctl enable --now docker
sudo usermod -aG docker ec2-user && newgrp docker

# 레포 클론
git clone https://github.com/hnmly/2026-terraform.git
cd 2026-terraform/05/1과제/terraform

# (1) 나머지 AWS 인프라 전체 생성 (KMS/S3/ECR/DynamoDB/EKS/노드/Lambda/WAF/CloudFront)
terraform init
terraform apply

# (2) 컨테이너 이미지 빌드 & ECR push
cd ../scripts && bash build-and-push.sh v1.0.0

# (3) kubectl 설정 + 클러스터 내부 배포 (앱/ALB/모니터링/fluent-bit)
aws eks update-kubeconfig --name wsc-eks-cluster --region ap-northeast-2
kubectl get nodes        # Ready 확인
TF_DIR=../terraform bash deploy-k8s.sh
```

> ⚠️ **State 주의**: 1단계(로컬)와 2단계(Bastion)가 같은 state를 공유해야 합니다.
> 가장 간단한 방법은 **S3 원격 백엔드**를 쓰는 것입니다. 백엔드를 안 쓴다면,
> 1단계 로컬 `terraform.tfstate`를 Bastion으로 복사하거나, **1·2단계 전체를 Bastion에서** 실행하세요.

### 3) CloudFront ↔ ALB 연결

Ingress가 만든 내부 ALB DNS를 변수에 넣어 CloudFront origin 연결 (state 있는 곳에서 실행):

```bash
ALB=$(aws elbv2 describe-load-balancers --names wsc-app-lb --query 'LoadBalancers[0].DNSName' --output text)
cd terraform
terraform apply -var="app_alb_dns=${ALB}"
```

## 검증

```bash
# 채점 스크립트
bash mark.sh
```

## 알려진 수동 보정 항목 (라이브 클러스터에서 검증 필요)

이 부분들은 노드/클러스터 런타임에 의존하므로 배포 후 확인·보정이 필요할 수 있습니다.

1. **노드 kubelet 도메인 `wsc.local`** — CoreDNS Corefile은 매니페스트로 변경되지만, Pod가
   `*.svc.wsc.local`을 resolve하려면 노드 kubelet `--cluster-domain=wsc.local`이 필요합니다.
   AL2023 노드는 `nodeadm` `kubelet.config.clusterDomain`으로 설정합니다(노드 LT user_data에 추가).
2. **노드 이름 `<INSTANCE_ID>.ec2.internal`** — kubelet `--hostname-override`로 보정.
3. **GET /v1/book → Lambda** — ALB Controller는 Lambda 타깃을 직접 만들지 못하므로, GET용
   Lambda Target Group을 별도 생성하고 `deploy-k8s.sh`의 `LAMBDA_TG_ARN`에 주입하거나
   Ingress `actions.get-book`로 라우팅합니다.
4. **이미지 8MB 이하** — `book`(8.7MB)을 수정할 수 없어 alpine+curl 최소 구성으로 압축 크기를
   맞춥니다. ECR `imageSizeInBytes`(압축)로 확인하고, 초과 시 베이스 이미지를 추가 경량화합니다.
5. **취약점 0** — `wsc-repo`는 scanOnPush 활성. 스캔 결과에 따라 베이스 이미지 패치가 필요할 수 있습니다.

## 정리

```bash
# 클러스터 내부 리소스(특히 ALB Ingress) 먼저 삭제 후 terraform destroy
kubectl delete -f k8s/ --ignore-not-found
cd terraform && terraform destroy
```
