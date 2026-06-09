# =============================================================================
# ECR 이미지 미러링
#  - workload 서브넷은 인터넷 없음(라우트 0개) → public.ecr.aws 접근 불가
#  - 필요한 외부 이미지를 프라이빗 ECR에 미러 → VPC 엔드포인트(ecr.api/dkr/s3)로 풀 가능
# =============================================================================

resource "aws_ecr_repository" "mirror_alb" {
  name                 = "mirror/aws-load-balancer-controller"
  image_tag_mutability = "MUTABLE"
  force_delete         = true
  tags                 = { Name = "mirror-alb-controller" }
}

resource "null_resource" "mirror_alb_image" {
  triggers = {
    repo = aws_ecr_repository.mirror_alb.repository_url
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e
      ECR_URL="${aws_ecr_repository.mirror_alb.repository_url}"
      REGISTRY=$(echo $ECR_URL | cut -d/ -f1)
      aws ecr get-login-password --region ${var.region} | docker login --username AWS --password-stdin $REGISTRY
      docker pull --platform linux/amd64 public.ecr.aws/eks/aws-load-balancer-controller:v3.4.0
      docker tag public.ecr.aws/eks/aws-load-balancer-controller:v3.4.0 $ECR_URL:v3.4.0
      docker push $ECR_URL:v3.4.0
    EOT
  }

  depends_on = [aws_ecr_repository.mirror_alb]
}

output "alb_controller_image" {
  description = "프라이빗 ECR에 미러된 ALB Controller 이미지 (deploy-k8s.sh에서 사용)"
  value       = "${aws_ecr_repository.mirror_alb.repository_url}:v3.4.0"
}
