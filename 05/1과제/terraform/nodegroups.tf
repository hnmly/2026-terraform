# =============================================================================
# EKS Managed Node Groups (app / addon / monitoring)
#  - t3.medium, AL2023, Workload Subnet, EBS KMS 암호화
#  - Label: type=app / type=addon / type=monitoring
#  - Bastion에서 SSH Password 접속, curl/ping 동작
# =============================================================================

# ---- Node IAM Role ----
resource "aws_iam_role" "node" {
  name               = "wsc-eks-node-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

resource "aws_iam_role_policy_attachment" "node" {
  for_each = toset([
    "arn:${local.partition}:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:${local.partition}:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:${local.partition}:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
    "arn:${local.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore",
    "arn:${local.partition}:iam::aws:policy/CloudWatchAgentServerPolicy",
  ])
  role       = aws_iam_role.node.name
  policy_arn = each.value
}

# ---- Node 추가 보안그룹 (Bastion -> SSH 22) ----
resource "aws_security_group" "node" {
  name        = "wsc-node-sg"
  description = "Extra SG for nodes - allow SSH from bastion"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "SSH from bastion"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "wsc-node-sg" }
}

# ---- 노드 user_data (MIME): SSH 패스워드 + 패키지 ----
# EKS 관리형 노드그룹(AL2023)은 nodeadm 부트스트랩을 자동 병합한다.
locals {
  node_user_data = base64encode(<<-EOT
    MIME-Version: 1.0
    Content-Type: multipart/mixed; boundary="==WSC=="

    --==WSC==
    Content-Type: text/x-shellscript; charset="us-ascii"

    #!/bin/bash
    set -x
    # 채점용 SSH 패스워드 접속 허용
    echo "ec2-user:${var.ssh_password}" | chpasswd
    echo "PasswordAuthentication yes" > /etc/ssh/sshd_config.d/60-wsc.conf
    systemctl restart sshd || true
    # curl/ping 동작 보장
    dnf install -y iputils || true

    --==WSC==--
  EOT
  )
}

# ---- Launch Template (EBS KMS 암호화) - 노드그룹별 (인스턴스 Name 태그 분리) ----
locals {
  node_groups = {
    app        = { name = "wsc-app-node", label = "app" }
    addon      = { name = "wsc-addon-node", label = "addon" }
    monitoring = { name = "wsc-monitoring-node", label = "monitoring" }
  }
}

resource "aws_launch_template" "node" {
  for_each    = local.node_groups
  name_prefix = "${each.value.name}-"

  vpc_security_group_ids = [
    aws_eks_cluster.this.vpc_config[0].cluster_security_group_id,
    aws_security_group.node.id,
  ]

  user_data = local.node_user_data

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = 30
      volume_type           = "gp3"
      encrypted             = true
      kms_key_id            = aws_kms_key.main.arn
      delete_on_termination = true
    }
  }

  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
    # Pod에서 노드 IMDS 사용 차단을 위해 hop limit 1
    http_put_response_hop_limit = 1
  }

  tag_specifications {
    resource_type = "instance"
    tags          = { Name = each.value.name }
  }
}

# ---- 3개 Managed Node Group ----
resource "aws_eks_node_group" "this" {
  for_each = local.node_groups

  cluster_name    = aws_eks_cluster.this.name
  node_group_name = each.value.name
  node_role_arn   = aws_iam_role.node.arn
  ami_type        = "AL2023_x86_64_STANDARD"
  instance_types  = [var.node_instance_type]

  subnet_ids = [
    aws_subnet.this["workload_a"].id,
    aws_subnet.this["workload_c"].id,
  ]

  scaling_config {
    desired_size = 2
    min_size     = 2
    max_size     = 3
  }

  launch_template {
    id      = aws_launch_template.node[each.key].id
    version = aws_launch_template.node[each.key].latest_version
  }

  labels = {
    type = each.value.label
  }

  depends_on = [
    aws_iam_role_policy_attachment.node,
    aws_vpc_endpoint.interface,
    aws_vpc_endpoint.s3,
    aws_vpc_endpoint.dynamodb,
  ]
}
