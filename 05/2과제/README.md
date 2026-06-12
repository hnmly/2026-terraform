# 05 2과제 - module-1(EKS Scaling) / module-3(Container Logging)

## 구조

```
module-1/
├── infra/   ← Step 1: VPC, Bastion, SQS, EKS, NodeGroup
└── k8s/     ← Step 2: Namespace, Deployment, KEDA, Karpenter

module-3/    ← 단일 (EKS 클러스터 포함 + Loki/Grafana)
```

---

## 0. 사전 준비 (CloudShell)

```bash
sudo yum install -y yum-utils
sudo yum-config-manager --add-repo https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo
sudo yum -y install terraform

cd ~
git clone https://github.com/hnmly/2026-terraform.git
```

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
cd ~/2026-terraform/05/2*/module-3
terraform init
terraform apply -auto-approve -var pin=<비번호>
# ⏱ ~20분
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
