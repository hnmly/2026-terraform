#!/usr/bin/env bash
# =============================================================================
# book 이미지 빌드 & ECR push (docker + awscli 필요)
# 사용: bash build-and-push.sh
# =============================================================================
set -euo pipefail

REGION="ap-northeast-2"
TAG="${1:-v1.0.0}"
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
ECR="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"
REPO="wsc-repo"
DOCKER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../docker" && pwd)"

aws ecr get-login-password --region "$REGION" | docker login --username AWS --password-stdin "$ECR"

# linux/amd64 (x86) 이미지 빌드
docker buildx build --platform linux/amd64 -t "${ECR}/${REPO}:${TAG}" --push "$DOCKER_DIR"

echo "Pushed ${ECR}/${REPO}:${TAG}"
echo "이미지 크기 확인:"
aws ecr describe-images --repository-name "$REPO" --region "$REGION" \
  --query "imageDetails[?imageTags[0]=='${TAG}'].imageSizeInBytes" --output text \
  | awk '{printf "%.2f MB\n", $1/1024/1024}'
echo "취약점 스캔 결과:"
aws ecr describe-image-scan-findings --repository-name "$REPO" --image-id imageTag="$TAG" \
  --region "$REGION" --query "imageScanFindings.findingSeverityCounts" --output text 2>/dev/null || echo "(스캔 진행 중)"
