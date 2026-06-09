#!/usr/bin/env bash
# =============================================================================
# terraform-apply.sh — "있으면 import, 없으면 새로 생성" 자동화 wrapper
#  main/ 디렉터리에서 실행. 하드코딩 없이 동적 조회.
#  사용: bash terraform-apply.sh [추가 terraform apply 옵션]
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")"

REGION="${AWS_DEFAULT_REGION:-ap-northeast-2}"

echo ">>> terraform init"
terraform init -input=false

# --- WAF (wsc-waf, CLOUDFRONT scope = us-east-1) ---
WAF_ID=$(aws wafv2 list-web-acls --scope CLOUDFRONT --region us-east-1 \
  --query "WebACLs[?Name=='wsc-waf'].Id" --output text 2>/dev/null || true)
if [ -n "$WAF_ID" ] && [ "$WAF_ID" != "None" ]; then
  WAF_ARN=$(aws wafv2 list-web-acls --scope CLOUDFRONT --region us-east-1 \
    --query "WebACLs[?Name=='wsc-waf'].ARN" --output text)
  echo ">>> wsc-waf 발견 → import"
  terraform import -input=false aws_wafv2_web_acl.waf "$WAF_ID/wsc-waf/CLOUDFRONT" 2>/dev/null || true
fi

# --- OAC (wsc-s3-oac-*) — random suffix라 기본적으로 충돌 안 남. skip ---

# --- KMS alias (alias/wsc-kms-*) — name_prefix라 충돌 안 남. skip ---

# --- EKS 로그그룹 — Terraform에서 안 만듦. skip ---

echo ">>> terraform apply"
terraform apply "$@"
