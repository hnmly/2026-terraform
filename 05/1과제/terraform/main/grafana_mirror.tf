# =============================================================================
# Grafana 이미지 미러 (Docker Hub → 프라이빗 ECR)
#  - Docker Hub는 pull-through cache에 자격증명이 필요하므로,
#    인터넷이 되는 Bastion에서 직접 pull → push 한다 (Docker Hub 계정 불필요).
#  - grafana 차트가 쓰는 이미지 3종을 고정 태그로 미러.
# =============================================================================

locals {
  grafana_images = {
    "grafana/grafana"      = "11.1.0"
    "kiwigrid/k8s-sidecar" = "1.27.4"
    "library/busybox"      = "1.31.1"
  }
}

resource "aws_ecr_repository" "grafana_mirror" {
  for_each             = local.grafana_images
  name                 = "docker-hub/${each.key}"
  image_tag_mutability = "MUTABLE"
  force_delete         = true
}

resource "null_resource" "grafana_mirror" {
  for_each = local.grafana_images

  triggers = {
    image = "${each.key}:${each.value}"
    repo  = aws_ecr_repository.grafana_mirror[each.key].repository_url
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e
      ECR_URL="${aws_ecr_repository.grafana_mirror[each.key].repository_url}"
      REGISTRY=$(echo $ECR_URL | cut -d/ -f1)
      aws ecr get-login-password --region ${var.region} | docker login --username AWS --password-stdin $REGISTRY
      docker pull --platform linux/amd64 docker.io/${each.key}:${each.value}
      docker tag docker.io/${each.key}:${each.value} $ECR_URL:${each.value}
      docker push $ECR_URL:${each.value}
    EOT
  }

  depends_on = [aws_ecr_repository.grafana_mirror]
}
