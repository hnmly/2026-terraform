# 05 2과제 - module-1(EKS Scaling) / module-3(Container Logging)

> ⚠️ **중요 - 실행 위치**
> - **infra** (VPC/EKS/EC2 등 AWS 리소스): **CloudShell**에서 apply
> - **k8s** (Namespace/Helm/KEDA/Karpenter/Loki/Grafana): 반드시 **Bastion에서 apply**
>   (AWS 계정 root 유저는 EKS 클러스터 API 인증이 불가. Bastion 역할은 ClusterAdmin access entry 보유)

## 구조

```
module-1/
├── infra/   ← Step 1: VPC, Bastion, SQS, EKS, NodeGroup
└── k8s/     ← Step 2: Namespace, Deployment, KEDA, Karpenter

module-3/
├── infra/   ← Step 1: VPC, EC2(앱+FluentBit), EKS, EBS CSI
└── k8s/     ← Step 2: Loki, Grafana, FluentBit 연동
```

---

## 0. 사전 준비 (CloudShell)

```bash
# Terraform 설치
sudo yum install -y unzip && curl -fsSLo /tmp/tf.zip https://releases.hashicorp.com/terraform/1.13.4/terraform_1.13.4_linux_amd64.zip && sudo unzip -o /tmp/tf.zip -d /usr/local/bin/ && terraform version

# 공유 플러그인 캐시 (CloudShell 1GB 용량 부족 방지 - 한 번만)
mkdir -p ~/.terraform.d/plugin-cache
cat > ~/.terraformrc <<'RC'
plugin_cache_dir = "$HOME/.terraform.d/plugin-cache"
RC

cd ~
git clone https://github.com/hnmly/2026-terraform.git
```

> 용량 부족(`no space left`) 시: `find ~/2026-terraform -type d -name ".terraform" -exec rm -rf {} +` 로 중복 캐시 정리 후 재시도.

---

## 1. module-1 (EKS Scaling, ap-northeast-2)

### Step 1: 인프라 — CloudShell에서
```bash
cd ~/2026-terraform/05/2*/module-1/infra
terraform init && terraform apply -auto-approve
# ⏱ ~15분 (EKS + NodeGroup + Bastion)
```

### Step 2: K8s 워크로드 — Bastion에서 (root는 EKS 인증 불가)
```bash
# Bastion 접속 (SSM 또는 SSH)
IID=$(aws ec2 describe-instances --region ap-northeast-2 \
  --filters "Name=tag:Name,Values=wsc-scaling-bastion" "Name=instance-state-name,Values=running" \
  --query "Reservations[0].Instances[0].InstanceId" --output text)
aws ssm start-session --region ap-northeast-2 --target $IID
sudo su - ec2-user

# Bastion 안에서: terraform 없으면 설치 (예전에 만든 bastion 대비)
command -v terraform || {
  sudo yum install -y unzip && curl -fsSLo /tmp/tf.zip https://releases.hashicorp.com/terraform/1.13.4/terraform_1.13.4_linux_amd64.zip && sudo unzip -o /tmp/tf.zip -d /usr/local/bin/ && terraform version
}

git clone https://github.com/hnmly/2026-terraform.git
cd 2026-terraform/05/2*/module-1/k8s
terraform init && terraform apply -auto-approve
# ⏱ ~5분 (KEDA + Karpenter + Deployment)
```

---

## 2. module-3 (Container Logging, ap-northeast-1)

### Step 1: 인프라 — CloudShell에서
```bash
cd ~/2026-terraform/05/2*/module-3/infra
terraform init && terraform apply -auto-approve
# ⏱ ~18분 (EKS + EC2(앱+FluentBit) + EBS CSI)
```

### Step 2: 로깅 스택 — Bastion(EC2)에서
```bash
# Bastion(EC2) 접속
IID=$(aws ec2 describe-instances --region ap-northeast-1 \
  --filters "Name=tag:Name,Values=wsc-logging-app-bastion" "Name=instance-state-name,Values=running" \
  --query "Reservations[0].Instances[0].InstanceId" --output text)
aws ssm start-session --region ap-northeast-1 --target $IID
sudo su - ec2-user

# Bastion 안에서: terraform 없으면 설치 (예전에 만든 bastion 대비)
command -v terraform || {
  sudo yum install -y unzip && curl -fsSLo /tmp/tf.zip https://releases.hashicorp.com/terraform/1.13.4/terraform_1.13.4_linux_amd64.zip && sudo unzip -o /tmp/tf.zip -d /usr/local/bin/ && terraform version
}

git clone https://github.com/hnmly/2026-terraform.git
cd 2026-terraform/05/2*/module-3/k8s
terraform init && terraform apply -auto-approve -var pin=<비번호>
# ⏱ ~7분 (Loki + Grafana + FluentBit 연동)
```

> `pin`은 본인 비번호 (Grafana 계정: `wsc2026-admin-<pin>` / `admin<pin>!`)

---

## 3. Bastion 접속 & 채점

Bastion 부팅 시 자동 구성:
- kubectl, eksctl, helm 설치
- SSH 패스워드 `Skill53##` (ec2-user)
- `~/marking/` 디렉터리
- `~/set-kubeconfig.sh`

```bash
# SSH 접속
ssh ec2-user@<Bastion-IP>    # 패스워드: Skill53##

# kubeconfig 설정
~/set-kubeconfig.sh

# 채점 스크립트 실행
cd ~/marking
./mark1.sh   # module-1
./mark3.sh   # module-3
```

채점 스크립트 업로드 (CloudShell → Bastion):
```bash
scp mark1.sh ec2-user@<IP>:~/marking/
```

---

## 4. 검증

```bash
# module-1
kubectl get ns wsc-scaling
kubectl get deploy -n wsc-scaling
kubectl get scaledobject -n wsc-scaling
kubectl get nodepool

# module-3
kubectl get pods,svc -n wsc-logging
curl http://<EC2-IP>:5000/health
curl "http://<EC2-IP>:5000/generate?count=30"
```
