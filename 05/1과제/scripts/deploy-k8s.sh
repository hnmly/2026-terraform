#!/usr/bin/env bash
# =============================================================================
# EKS 클러스터 내부 리소스 배포 (Bastion에서 실행)
#  사전: terraform apply 완료, build-and-push.sh 로 이미지 push 완료
#  - kubeconfig 설정 -> addons(ALB controller, EBS CSI) -> CoreDNS -> app
#    -> fluent-bit -> monitoring(prometheus/grafana)
#
#  terraform output 값을 환경변수로 주입하여 매니페스트(envsubst) 렌더링한다.
#  TF_DIR 은 terraform 디렉터리 경로.
# =============================================================================
set -euo pipefail

REGION="ap-northeast-2"
CLUSTER="wsc-eks-cluster"
TF_DIR="${TF_DIR:-../terraform}"
K8S_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../k8s" && pwd)"

tfout() { terraform -chdir="$TF_DIR" output -raw "$1"; }

export ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
export ECR_IMAGE="$(tfout ecr_repository_url):v1.0.0"
export APP_SA_ROLE_ARN="$(tfout app_sa_role_arn)"
export FLUENTBIT_ROLE_ARN="$(tfout fluentbit_role_arn)"
export ALB_ROLE_ARN="$(tfout alb_controller_role_arn)"
export EBS_ROLE_ARN="$(tfout ebs_csi_role_arn)"
export KMS_KEY_ARN="$(tfout kms_key_arn)"
export LAMBDA_ARN="$(tfout lambda_arn)"
PUB_A=$(aws ec2 describe-subnets --filters Name=tag:Name,Values=wsc-public-a --query "Subnets[0].SubnetId" --output text)
PUB_C=$(aws ec2 describe-subnets --filters Name=tag:Name,Values=wsc-public-c --query "Subnets[0].SubnetId" --output text)
PRIV_A=$(aws ec2 describe-subnets --filters Name=tag:Name,Values=wsc-private-a --query "Subnets[0].SubnetId" --output text)
PRIV_C=$(aws ec2 describe-subnets --filters Name=tag:Name,Values=wsc-private-c --query "Subnets[0].SubnetId" --output text)
export APP_LB_SUBNETS="${PRIV_A},${PRIV_C}"
export ADDON_LB_SUBNETS="${PUB_A},${PUB_C}"
# Lambda Target Group은 ALB Controller가 만들 수 없으므로 GET용 별도 TG를 수동 생성 후 ARN 주입 필요
export LAMBDA_TG_ARN="${LAMBDA_TG_ARN:-PLACEHOLDER_LAMBDA_TG_ARN}"

# 1) kubeconfig
aws eks update-kubeconfig --name "$CLUSTER" --region "$REGION"

# 2) Helm repo
helm repo add eks https://aws.github.io/eks-charts
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

# 3) 네임스페이스
kubectl apply -f "$K8S_DIR/00-namespaces.yaml"

# 4) AWS Load Balancer Controller (addon 노드)
kubectl create sa aws-load-balancer-controller -n kube-system \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl annotate sa aws-load-balancer-controller -n kube-system \
  eks.amazonaws.com/role-arn="$ALB_ROLE_ARN" --overwrite
helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName="$CLUSTER" \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set nodeSelector.type=addon \
  --set region="$REGION" \
  --set vpcId="$(aws eks describe-cluster --name $CLUSTER --query cluster.resourcesVpcConfig.vpcId --output text)"

# 5) EBS CSI Driver (addon)
kubectl create sa ebs-csi-controller-sa -n kube-system \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl annotate sa ebs-csi-controller-sa -n kube-system \
  eks.amazonaws.com/role-arn="$EBS_ROLE_ARN" --overwrite
aws eks create-addon --cluster-name "$CLUSTER" --addon-name aws-ebs-csi-driver \
  --service-account-role-arn "$EBS_ROLE_ARN" --region "$REGION" 2>/dev/null || true

# 6) CoreDNS wsc.local + StorageClass
kubectl apply -f "$K8S_DIR/30-coredns-wsc-local.yaml"
kubectl -n kube-system rollout restart deploy/coredns
envsubst < "$K8S_DIR/20-storageclass.yaml" | kubectl apply -f -

# 7) 애플리케이션
envsubst < "$K8S_DIR/10-app.yaml" | kubectl apply -f -

# 8) Fluent Bit
envsubst < "$K8S_DIR/40-fluent-bit.yaml" | kubectl apply -f -

# 9) Monitoring (PVC -> prometheus -> grafana -> dashboard -> ingress)
kubectl apply -f "$K8S_DIR/50-monitoring-pvc.yaml"
helm upgrade --install prometheus prometheus-community/prometheus \
  -n monitoring -f "$K8S_DIR/helm-values/prometheus-values.yaml"
helm upgrade --install grafana grafana/grafana \
  -n monitoring -f "$K8S_DIR/helm-values/grafana-values.yaml"
kubectl apply -f "$K8S_DIR/helm-values/grafana-dashboard-configmap.yaml"
envsubst < "$K8S_DIR/60-monitoring-ingress.yaml" | kubectl apply -f -

echo "배포 완료. ALB 생성까지 수 분 소요."
echo "wsc-app-lb DNS 확인 후 terraform 변수 app_alb_dns 에 넣고 재적용하여 CloudFront origin 연결:"
echo "  aws elbv2 describe-load-balancers --names wsc-app-lb --query 'LoadBalancers[0].DNSName' --output text"
