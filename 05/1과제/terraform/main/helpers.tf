# =============================================================================
# 충돌 방지용 리소스
# =============================================================================

resource "random_id" "oac" {
  byte_length = 4
}

# WAF는 채점이 고정 이름(wsc-waf)으로 찾으므로, 이미 있으면 import해서 관리한다.
# 없으면 새로 만든다. (terraform import를 apply 전 한 번 수동으로 해도 되고,
# 아래 import 블록(TF 1.5+)은 plan 시 자동으로 import를 시도한다.)
import {
  to = aws_wafv2_web_acl.waf
  id = "7fd0b279-47ec-4f41-a48f-9f4af588d63b/wsc-waf/CLOUDFRONT"
}
