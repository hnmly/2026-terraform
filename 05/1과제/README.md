# 2026 전국기능경기대회 클라우드컴퓨팅 제1과제 (05) — EKS 기반 Solution Architecture

ZTNA/MSA 컨셉의 콘서트 예약 REST API를 **EKS 기반**으로 구축하는 과제입니다.
AWS 인프라는 **Terraform**, 클러스터 내부 리소스는 **Kubernetes 매니페스트/Helm**으로 구성합니다.

> ℹ️ 문제 유의사항상 실제 경기에서는 콘솔/CLI 구축이 요구될 수 있으나, 본 레포는
> **학습/연습용 Terraform + K8s 재현**입니다. 채점 스크립트(`mark.sh`)의 항목 기준에 맞춰 작성했습니다.

## 디렉터리 구조

```
05/1과제/
├── terraform/
│   ├── bootstrap/     # [로컬 실행] VPC(네트워크) + Bastion 만 생성
│   └── main/          # [Bastion 실행] 나머지 전부. VPC/Bastion은 data 소스로 조회만
│       ├── *.tf
│       ├── policies/alb-controller-policy.json
│       └── lambda/lambda_function.py   # GET /v1/book
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


## 배포 방법

`bootstrap/`(로컬) → `main/`(Bastion) → `deploy-k8s.sh`(Bastion) 순으로 실행.
**다른 계정에서 처음부터 해도 수동 입력 없이 한 번에 완료**됩니다.

---

### 0) 도구 설치

**로컬 PC (Windows PowerShell)**

```powershell
winget install --id HashiCorp.Terraform -e --source winget
winget install --id Amazon.AWSCLI -e --source winget
terraform version && aws --version
aws configure   # region: ap-northeast-2
```

**Bastion (Amazon Linux 2023)** — 2단계에서 설치

```bash
sudo dnf install -y dnf-plugins-core
sudo dnf config-manager --add-repo https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo
sudo dnf install -y terraform docker git
sudo systemctl enable --now docker
sudo usermod -aG docker ec2-user && newgrp docker
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

---

### 1단계 — 로컬: VPC + Bastion

```powershell
cd 05\1과제\terraform\bootstrap
terraform init
terraform apply
terraform output bastion_public_ip
```

---

### 2단계 — Bastion 접속

```bash
ssh ec2-user@<BASTION_IP>    # PW: Skill53##
```

---

### 3단계 — Bastion: 인프라 생성 (ALB + CloudFront 포함)

```bash
git clone https://github.com/hnmly/2026-terraform.git
cd 2026-terraform/05/1과제/terraform/main
rm -rf .terraform .terraform.lock.hcl
terraform init
terraform apply
```

> ALB(wsc-app-lb/wsc-addon-lb), CloudFront, WAF 모두 Terraform이 직접 생성.
> 수동 변수 입력 불필요.

---

### 4단계 — Bastion: 이미지 빌드 & ECR 푸시

```bash
cd ~/2026-terraform/05/1과제/scripts
bash build-and-push.sh v1.0.0
```

---

### 5단계 — Bastion: K8s 배포

```bash
aws eks update-kubeconfig --name wsc-eks-cluster --region ap-northeast-2
kubectl get nodes    # Ready 확인

cd ~/2026-terraform/05/1과제/scripts
TF_DIR=../terraform/main bash deploy-k8s.sh
```

> deploy-k8s.sh: ALB Controller + EBS CSI + 앱 + Fluent Bit + Prometheus + Grafana +
> **TargetGroupBinding**(Terraform TG에 Pod IP 자동 등록) 배포.

---

### 6단계 — Lambda 런타임 변경

```bash
aws lambda update-function-configuration \
  --function-name wsc-get-table-function \
  --runtime python3.14 --region ap-northeast-2
```

---

### 7단계 — 채점

```bash
cd ~ && ./mark.sh
```

---

## 정리 (Teardown)

```bash
# (Bastion)
helm uninstall grafana prometheus -n monitoring 2>/dev/null
kubectl delete -f ~/2026-terraform/05/1과제/k8s/ --ignore-not-found
cd ~/2026-terraform/05/1과제/terraform/main && terraform destroy

# (로컬)
cd terraform/bootstrap && terraform destroy
```
