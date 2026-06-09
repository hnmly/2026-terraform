# =============================================================================
# "없으면 생성, 있으면 기존 것 사용" 패턴
#  - data 소스로 기존 존재 여부 조회
#  - count = 0/1 로 생성 여부 분기
#  - local로 최종 ID/ARN 통합 참조
# =============================================================================

# ---- WAF ----
data "external" "existing_waf" {
  program = ["bash", "-c", <<-EOT
    ARN=$(aws wafv2 list-web-acls --scope CLOUDFRONT --region us-east-1 --query "WebACLs[?Name=='wsc-waf'].ARN | [0]" --output text 2>/dev/null)
    if [ "$ARN" = "None" ] || [ -z "$ARN" ]; then
      echo '{"arn":""}'
    else
      echo "{\"arn\":\"$ARN\"}"
    fi
  EOT
  ]
}

locals {
  waf_exists = data.external.existing_waf.result.arn != ""
  waf_arn    = local.waf_exists ? data.external.existing_waf.result.arn : try(aws_wafv2_web_acl.waf[0].arn, "")
}

# ---- OAC ----
data "external" "existing_oac" {
  program = ["bash", "-c", <<-EOT
    ID=$(aws cloudfront list-origin-access-controls --query "OriginAccessControlList.Items[?Name=='wsc-s3-oac'].Id | [0]" --output text 2>/dev/null)
    if [ "$ID" = "None" ] || [ -z "$ID" ]; then
      echo '{"id":""}'
    else
      echo "{\"id\":\"$ID\"}"
    fi
  EOT
  ]
}

locals {
  oac_exists = data.external.existing_oac.result.id != ""
  oac_id     = local.oac_exists ? data.external.existing_oac.result.id : try(aws_cloudfront_origin_access_control.s3[0].id, "")
}

# ---- KMS alias ----
data "external" "existing_kms" {
  program = ["bash", "-c", <<-EOT
    KEY=$(aws kms describe-key --key-id alias/wsc-kms --query "KeyMetadata.Arn" --output text --region ap-northeast-2 2>/dev/null)
    if [ $? -ne 0 ] || [ -z "$KEY" ] || [ "$KEY" = "None" ]; then
      echo '{"arn":""}'
    else
      echo "{\"arn\":\"$KEY\"}"
    fi
  EOT
  ]
}

locals {
  kms_alias_exists = data.external.existing_kms.result.arn != ""
}
