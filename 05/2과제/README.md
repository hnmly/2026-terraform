# 05 2과제 - module-1(EKS Scaling) / module-3(Container Logging)

문제지/채점기준표 기준으로 **인프라 + Kubernetes 워크로드를 전부 Terraform으로 자동 구성**합니다.
수동 후속 작업은 원칙적으로 없으며, 채점용 접속/검증만 하면 됩니다.

## 자동화 범위

| 모듈 | Terraform이 생성하는 것 |
|---|---|
| module-1 | VPC/서브넷/IGW/NAT, Bastion(EIP), SQS, EKS 1.35, 관리형 NodeGroup(min2/max10), **Namespace·Deployment·KEDA·ScaledObject·Karpenter(NodePool/EC2NodeClass) 까지** |
| module-3 | VPC/서브넷/IGW/NAT, EC2(앱+Fluent Bit), EKS 1.35, NodeGroup, EBS CSI+gp3 SC, **Loki(SingleBinary/NLB)·Grafana(NLB/대시보드)·Fluent Bit→Loki 연동까지** |

---

## 0. 사전 준비 (CloudShell)

```bash
# Terraform 설치
sudo yum install -y yum-utils
sudo yum-config-manager --add-repo https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo
sudo yum -y install terraform
terraform --version

# 코드 다운로드
cd ~
git clone https://github.com/hnmly/2026-terraform.git
cd 2026-terraform
```

> CloudShell은 한글 폴더명 입력이 불편하므로 glob 패턴(`05/2*/...`)으로 이동합니다.

---

## 1. module-1 배포 (EKS Scaling, ap-northeast-2)

```bash
cd ~/2026-terraform/05/2*/module-1

terraform init
terraform apply -auto-approve
# ⏱ EKS + NodeGroup + KEDA + Karpenter 까지 약 20~25분
```

> ⚠️ 동일 apply에서 EKS 클러스터 생성과 Helm/Kubernetes 리소스를 함께 적용합니다.
> 첫 apply에서 드물게 `Unauthorized`/`connection refused` 같은 일시적 인증 오류가 나면
> **`terraform apply -auto-approve`를 한 번 더 실행**하면 이어서 완료됩니다.

자동 구성 결과:
- Namespace `wsc-scaling`, Deployment `wsc-scaling-deploy`(busybox, 2 replicas, label dedicated=scaling)
- KEDA 설치 + ScaledObject `wsc-scaling-scaledobject` (pollingInterval 30, queueLength 5, min 2)
- Karpenter 설치 + NodePool `wsc-scaling-nodepool` (CPU 100 / Memory 200Gi)

---

## 2. module-3 배포 (Container Logging, ap-northeast-1)

```bash
cd ~/2026-terraform/05/2*/module-3

terraform init
# 비번호를 pin 변수로 전달 (Grafana 계정: wsc2026-admin-<pin> / admin<pin>!)
terraform apply -auto-approve -var pin=07
# ⏱ EKS + Loki + Grafana + Fluent Bit 연동까지 약 20~25분
```

자동 구성 결과:
- EC2 `wsc-logging-app-bastion` : Docker로 flask 앱(:5000) 실행 + Fluent Bit(systemd)
- EBS CSI Driver + 기본 StorageClass `gp3`
- Loki(SingleBinary, filesystem PVC 10Gi) + `loki-nlb`(LoadBalancer/NLB :3100)
- Grafana(NLB) + Loki DataSource + `WSC2026 Container Logs` 대시보드(4종 패널, 5초 새로고침)
- Fluent Bit → Loki NLB 엔드포인트 **SSM으로 자동 주입** (수동 설정 불필요)

> `pin`을 안 주면 기본값 `00`이 사용됩니다. 반드시 본인 비번호로 지정하세요.

---

## 3. 채점용 Bastion 접속 & 채점 스크립트 배치

두 모듈의 Bastion(EC2)은 부팅 시 자동으로 아래가 구성됩니다.
- `kubectl`, `helm` 설치 / `ec2-user` SSH 패스워드 접속 허용(패스워드 `Skill53##`)
- 채점 디렉터리 `/home/ec2-user/marking/` / kubeconfig 헬퍼 `~/set-kubeconfig.sh`

### SSM Session Manager 접속 (키 불필요, 권장)

```bash
# module-1 Bastion
IID=$(aws ec2 describe-instances --region ap-northeast-2 \
  --filters "Name=tag:Name,Values=wsc-scaling-bastion" "Name=instance-state-name,Values=running" \
  --query "Reservations[0].Instances[0].InstanceId" --output text)
aws ssm start-session --region ap-northeast-2 --target $IID

# module-3 Bastion(EC2)
IID=$(aws ec2 describe-instances --region ap-northeast-1 \
  --filters "Name=tag:Name,Values=wsc-logging-app-bastion" "Name=instance-state-name,Values=running" \
  --query "Reservations[0].Instances[0].InstanceId" --output text)
aws ssm start-session --region ap-northeast-1 --target $IID

# 접속 후
sudo su - ec2-user
~/set-kubeconfig.sh    # kubeconfig 설정 + kubectl get nodes
```

### SSH 패스워드 접속 (채점관 방식)

```bash
aws ec2 describe-instances --region ap-northeast-2 \
  --filters "Name=tag:Name,Values=wsc-scaling-bastion" \
  --query "Reservations[0].Instances[0].PublicIpAddress" --output text
ssh ec2-user@<IP>     # 패스워드: Skill53##
```

### 채점 스크립트(mark1.sh / mark3.sh) 복사

```bash
# SSH/scp
scp mark1.sh ec2-user@<IP>:/home/ec2-user/marking/      # 패스워드: Skill53##

# 또는 SSM으로 업로드 (로컬에 mark1.sh가 있을 때)
B64=$(base64 -w0 mark1.sh)
aws ssm send-command --region ap-northeast-2 --instance-ids $IID \
  --document-name "AWS-RunShellScript" \
  --parameters "commands=[\"echo $B64 | base64 -d > /home/ec2-user/marking/mark1.sh\",\"chmod +x /home/ec2-user/marking/mark1.sh\"]"

# Bastion에서 실행
cd /home/ec2-user/marking && ./mark1.sh   # module-1
cd /home/ec2-user/marking && ./mark3.sh   # module-3
```

---

## 4. 검증

```bash
# module-1 (Bastion에서)
~/set-kubeconfig.sh
kubectl get deploy -n wsc-scaling
kubectl get scaledobject -n wsc-scaling
kubectl get nodepool,ec2nodeclass
# SQS에 메시지 100건 넣고 Pod/Node 증가 확인
SQS_URL=$(aws sqs get-queue-url --queue-name wsc-scaling-sqs --query QueueUrl --output text)
for n in $(seq 1 100); do aws sqs send-message --queue-url "$SQS_URL" --message-body "test $n" >/dev/null; done
watch kubectl get pods,nodes -n wsc-scaling

# module-3 (Bastion에서)
~/set-kubeconfig.sh
kubectl get pods,svc -n wsc-logging
EC2_IP=$(aws ec2 describe-instances --region ap-northeast-1 \
  --filters "Name=tag:Name,Values=wsc-logging-app-bastion" "Name=instance-state-name,Values=running" \
  --query "Reservations[0].Instances[0].PublicIpAddress" --output text)
curl http://$EC2_IP:5000/health
curl "http://$EC2_IP:5000/generate?count=30"
# Loki에 로그 도달 확인
LOKI_LB=$(kubectl get svc -n wsc-logging loki-nlb -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
curl -sG "http://$LOKI_LB:3100/loki/api/v1/query_range" --data-urlencode 'query={namespace="wsc-app-log"}'
```

---

## 참고 / 주의

- Helm 차트(특히 Loki SingleBinary, Karpenter, Grafana)는 버전에 민감합니다.
  apply가 차트 단계에서 실패하면 해당 `helm_release`의 `version` 값을 환경에 맞게 조정 후 재실행하세요.
- module-3의 Fluent Bit→Loki 자동 주입은 `aws` CLI가 있는 환경(CloudShell)에서 apply할 때 동작합니다.
- 리소스 정리: 각 모듈 디렉터리에서 `terraform destroy -auto-approve`
  (module-3는 `-var pin=<비번호>` 동일하게 전달).
