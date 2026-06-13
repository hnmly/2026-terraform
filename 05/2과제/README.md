# 05 2과제 - module-1(EKS Scaling) / module-3(Container Logging)

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
sudo yum install -y yum-utils
sudo yum-config-manager --add-repo https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo
sudo yum -y install terraform

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

```bash
# Step 1: 인프라
cd ~/2026-terraform/05/2*/module-1/infra
terraform init
terraform apply -auto-approve
# ⏱ ~15분 (EKS 클러스터 + NodeGroup)

# Step 2: K8s 워크로드 (Step 1 완료 후)
cd ../k8s
terraform init
terraform apply -auto-approve
# ⏱ ~5분 (KEDA + Karpenter + Deployment)
```

---

## 2. module-3 (Container Logging, ap-northeast-1)

```bash
# Step 1: 인프라 (VPC, EC2+앱+FluentBit, EKS, EBS CSI)
cd ~/2026-terraform/05/2*/module-3/infra
terraform init
terraform apply -auto-approve
# ⏱ ~18분

# Step 2: 로깅 스택 (Loki, Grafana, FluentBit 연동) - Step 1 완료 후
cd ../k8s
terraform init
terraform apply -auto-approve -var pin=<비번호>
# ⏱ ~7분
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
