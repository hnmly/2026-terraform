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

Terraform을 **`bootstrap/`(로컬)** → **`main/`(Bastion)** 순으로 실행합니다.
`main/`은 VPC/Bastion을 data 소스로 조회만 하므로 중복 생성되지 않습니다.

---

### 0) 도구 설치

**로컬 PC (Windows PowerShell)**

```powershell
winget install --id HashiCorp.Terraform -e --source winget
winget install --id Amazon.AWSCLI -e --source winget
# 새 PowerShell 창 열고:
terraform version
aws --version
aws configure   # region: ap-northeast-2
```

**Bastion (Amazon Linux 2023)** — 2단계에서 설치

```bash
sudo dnf install -y dnf-plugins-core
sudo dnf config-manager --add-repo https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo
sudo dnf install -y terraform docker git
sudo systemctl enable --now docker
sudo usermod -aG docker ec2-user && newgrp docker
terraform version
```

> Bastion에는 awscli v2, kubectl, eksctl이 user_data로 이미 설치되어 있습니다.

---

### 1단계 — 로컬: VPC + Bastion 생성

```powershell
cd 05\1과제\terraform\bootstrap
terraform init
terraform apply
terraform output bastion_public_ip    # Bastion IP 메모
```

---

### 2단계 — Bastion 접속

```bash
ssh ec2-user@<BASTION_IP>
# 패스워드: Skill53##
```

---

### 3단계 — Bastion: 레포 클론 + main apply

```bash
git clone https://github.com/hnmly/2026-terraform.git
cd 2026-terraform/05/1과제/terraform/main
rm -rf .terraform .terraform.lock.hcl
terraform init
terraform apply
```

> WAF(`wsc-waf`), OAC(`wsc-s3-oac`) 등 이름 고정 리소스는 "있으면 기존 것 사용, 없으면 생성"
> 로직(`external` data + `count`)으로 처리됩니다. 에러 없이 한 번에 됩니다.

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
kubectl get nodes    # 전부 Ready 확인

cd ~/2026-terraform/05/1과제/scripts
TF_DIR=../terraform/main bash deploy-k8s.sh
```

---

### 6단계 — Bastion: CloudFront ↔ ALB 연결

Ingress가 ALB를 생성한 뒤(수 분 대기):

```bash
ALB=$(aws elbv2 describe-load-balancers --names wsc-app-lb --query 'LoadBalancers[0].DNSName' --output text)
cd ~/2026-terraform/05/1과제/terraform/main
terraform apply -var="app_alb_dns=${ALB}"
```

---

### 7단계 — 채점 (Bastion에서)

```bash
bash ~/mark.sh
```

> 채점 스크립트(`mark.sh`)는 kubectl을 사용하므로 **반드시 Bastion에서** 실행해야 합니다.
> (일반 CloudShell은 private EKS 엔드포인트에 접근 불가)

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

## 정리 (Teardown)

**삭제는 생성의 역순**입니다: K8s 리소스 → `main`(Bastion) → `bootstrap`(로컬).
(ALB Ingress를 먼저 지워야 ALB/보안그룹이 깔끔히 삭제됩니다.)

```bash
# 1) (Bastion) 클러스터 내부 리소스 삭제 - ALB Ingress 포함
kubectl delete -f k8s/60-monitoring-ingress.yaml --ignore-not-found
kubectl delete -f k8s/10-app.yaml --ignore-not-found
helm uninstall grafana prometheus -n monitoring 2>/dev/null
kubectl delete -f k8s/ --ignore-not-found

# 2) (Bastion) main 인프라 삭제
cd terraform/main
terraform destroy

# 3) (로컬) bootstrap(VPC+Bastion) 삭제
cd terraform/bootstrap
terraform destroy
```

### state가 꼬였거나 "already exists"가 반복될 때 (수동 정리)

로컬·Bastion에서 따로 apply해서 **리소스가 중복 생성**되었거나 state가 어긋난 경우,
`terraform destroy`가 깔끔히 안 될 수 있습니다. 이때는 `wsc-` 접두어 리소스를
**아래 순서로 직접 삭제**한 뒤 처음부터 다시 배포하세요.

```bash
R=ap-northeast-2

# (a) EKS 노드그룹 → 클러스터 (삭제에 수 분 소요)
for ng in wsc-app-node wsc-addon-node wsc-monitoring-node; do
  aws eks delete-nodegroup --cluster-name wsc-eks-cluster --nodegroup-name $ng --region $R 2>/dev/null
done
aws eks delete-cluster --name wsc-eks-cluster --region $R 2>/dev/null

# (b) Bastion EC2, Lambda
aws ec2 terminate-instances --region $R --instance-ids \
  $(aws ec2 describe-instances --region $R \
    --filters Name=tag:Name,Values=wsc-bastion Name=instance-state-name,Values=running,stopped \
    --query "Reservations[].Instances[].InstanceId" --output text)
aws lambda delete-function --function-name wsc-get-table-function --region $R 2>/dev/null

# (c) NAT GW → VPC 엔드포인트 → 서브넷/RT/IGW → VPC (VPC가 2개면 둘 다)
#     콘솔에서 wsc-vpc 들을 "VPC 삭제"하면 연결 리소스가 함께 정리됩니다.

# (d) CloudFront(비활성화 후 삭제) → WAF → OAC
aws wafv2 delete-web-acl --name wsc-waf --scope CLOUDFRONT --region us-east-1 ... # LockToken 필요

# (e) S3(비우고 삭제), ECR, DynamoDB
aws s3 rb s3://wsc-static-<ACCOUNT_ID> --force
aws ecr delete-repository --repository-name wsc-repo --force --region $R
aws dynamodb delete-table --table-name wsc-table --region $R

# (f) IAM 역할/정책/인스턴스프로파일, KMS alias, 로그그룹
#  - 역할은 정책 detach/inline 삭제 후 delete-role
#  - 인스턴스프로파일(wsc-bastion-profile)에서 역할 제거 후 삭제해야 wsc-bastion-role 삭제 가능
aws iam delete-policy --policy-arn arn:aws:iam::<ACCOUNT_ID>:policy/wsc-alb-controller-policy
aws kms delete-alias --alias-name alias/wsc-kms --region $R
aws logs delete-log-group --log-group-name /wsc/pod/log --region $R
aws logs delete-log-group --log-group-name /aws/eks/wsc-eks-cluster/cluster --region $R
```

> 정리 후 확인 (모두 비어 있어야 정상):
> ```bash
> aws ec2 describe-vpcs --filters Name=tag:Name,Values=wsc-vpc --query "Vpcs[].VpcId" --region ap-northeast-2
> aws iam list-roles --query "Roles[?starts_with(RoleName,'wsc-')].RoleName"
> ```

### 재발 방지
- **반드시 `bootstrap`은 로컬에서, `main`은 Bastion에서** 한 번씩만 apply하세요.
- 같은 설정을 두 곳에서 apply하지 마세요 (VPC 중복 생성의 원인).
- 더 확실히 하려면 **S3 원격 백엔드**를 구성해 state를 한 곳에서 공유하세요.
