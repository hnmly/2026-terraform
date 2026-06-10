# =============================================================================
# ECR Pull-Through Cache
#  - workload 서브넷은 인터넷이 없어 외부 레지스트리(public.ecr.aws/quay/registry.k8s.io)
#    이미지를 직접 못 당긴다.
#  - pull-through cache: 노드는 프라이빗 ECR(VPC 엔드포인트)로 당기고, ECR이 외부에서
#    자동으로 가져와 캐시한다.
#  - 이미지 경로: <account>.dkr.ecr.<region>.amazonaws.com/<prefix>/<원본경로>
# =============================================================================

resource "aws_ecr_pull_through_cache_rule" "ecr_public" {
  ecr_repository_prefix = "ecr-public"
  upstream_registry_url = "public.ecr.aws"
}

resource "aws_ecr_pull_through_cache_rule" "quay" {
  ecr_repository_prefix = "quay"
  upstream_registry_url = "quay.io"
}

resource "aws_ecr_pull_through_cache_rule" "k8s" {
  ecr_repository_prefix = "k8s"
  upstream_registry_url = "registry.k8s.io"
}

# Docker Hub (grafana 등)는 자격증명 필요. var.dockerhub_secret_arn 제공 시에만 생성.
resource "aws_ecr_pull_through_cache_rule" "docker_hub" {
  count                 = var.dockerhub_secret_arn != "" ? 1 : 0
  ecr_repository_prefix = "docker-hub"
  upstream_registry_url = "registry-1.docker.io"
  credential_arn        = var.dockerhub_secret_arn
}

# pull-through cache는 노드 역할의 인라인 정책(아래 node_ptc)으로 충분하다.
# (registry policy는 크로스계정용이라 불필요)

# 노드 역할에 pull-through cache 생성/임포트 권한 추가
resource "aws_iam_role_policy" "node_ptc" {
  name = "wsc-node-ecr-ptc"
  role = aws_iam_role.node.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "ecr:BatchImportUpstreamImage",
        "ecr:CreateRepository",
        "ecr:TagResource",
      ]
      Resource = "*"
    }]
  })
}

locals {
  ecr_registry_url = "${local.account_id}.dkr.ecr.${var.region}.amazonaws.com"
}

output "ecr_registry_url" {
  value = local.ecr_registry_url
}
