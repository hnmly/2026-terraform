# =====================================================================
# Module 3 - EC2 Fluent Bit에 Loki NLB 엔드포인트 자동 주입 (SSM)
# =====================================================================
# EC2 부팅 시 Fluent Bit 설정에는 LOKI_NLB_DNS 자리표시자가 들어가 있음.
# Loki NLB가 생성되면 그 DNS를 SSM으로 EC2에 주입하고 Fluent Bit을 재시작한다.
# (aws CLI가 있는 환경 - 예: CloudShell - 에서 terraform apply 시 자동 실행)

resource "null_resource" "configure_fluentbit" {
  triggers = {
    loki_host   = kubernetes_service.loki_nlb.status[0].load_balancer[0].ingress[0].hostname
    instance_id = aws_instance.app.id
  }

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = <<-EOT
      set -e
      LOKI_HOST="${kubernetes_service.loki_nlb.status[0].load_balancer[0].ingress[0].hostname}"
      INSTANCE_ID="${aws_instance.app.id}"
      echo "Loki NLB: $LOKI_HOST -> instance $INSTANCE_ID"

      # SSM agent 준비 대기
      for i in $(seq 1 30); do
        PING=$(aws ssm describe-instance-information --region ap-northeast-1 \
          --filters "Key=InstanceIds,Values=$INSTANCE_ID" \
          --query "InstanceInformationList[0].PingStatus" --output text 2>/dev/null || echo "None")
        [ "$PING" = "Online" ] && break
        echo "SSM not ready ($PING), retry $i..."; sleep 10
      done

      CMD_ID=$(aws ssm send-command --region ap-northeast-1 \
        --instance-ids "$INSTANCE_ID" \
        --document-name "AWS-RunShellScript" \
        --parameters "commands=[\"sed -i \\\"s/LOKI_NLB_DNS/$LOKI_HOST/g\\\" /etc/fluent-bit/fluent-bit.conf\",\"systemctl restart fluent-bit\",\"systemctl is-active fluent-bit\"]" \
        --query "Command.CommandId" --output text)
      echo "SSM Command: $CMD_ID"

      sleep 10
      aws ssm get-command-invocation --region ap-northeast-1 \
        --command-id "$CMD_ID" --instance-id "$INSTANCE_ID" \
        --query "StandardOutputContent" --output text || true
    EOT
  }

  depends_on = [
    aws_instance.app,
    kubernetes_service.loki_nlb,
  ]
}
