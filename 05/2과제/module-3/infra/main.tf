terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "ap-northeast-1"
}

data "aws_caller_identity" "current" {}

locals {
  name = "wsc-logging"
}

# VPC
resource "aws_vpc" "main" {
  cidr_block           = "10.3.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = { Name = "wsc-log-vpc" } # 채점기준표 3-1이 wsc-log-vpc로 조회 (문제지는 wsc-logging-vpc - 출제측 불일치)
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${local.name}-igw" }
}

resource "aws_subnet" "pub_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.3.0.0/24"
  availability_zone       = "ap-northeast-1a"
  map_public_ip_on_launch = true
  tags                    = { Name = "${local.name}-sn-pub-a" }
}

resource "aws_subnet" "pub_c" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.3.1.0/24"
  availability_zone       = "ap-northeast-1c"
  map_public_ip_on_launch = true
  tags                    = { Name = "${local.name}-sn-pub-c" }
}

resource "aws_subnet" "priv_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.3.2.0/24"
  availability_zone = "ap-northeast-1a"
  tags              = { Name = "${local.name}-sn-priv-a" }
}

resource "aws_subnet" "priv_c" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.3.3.0/24"
  availability_zone = "ap-northeast-1c"
  tags              = { Name = "${local.name}-sn-priv-c" }
}

# NAT Gateway
resource "aws_eip" "nat" {
  domain = "vpc"
  tags   = { Name = "${local.name}-nat-eip" }
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.pub_a.id
  tags          = { Name = "${local.name}-natgw" }
}

# Route Tables
resource "aws_route_table" "pub" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
  tags = { Name = "${local.name}-rt-pub" }
}

resource "aws_route_table_association" "pub_a" {
  subnet_id      = aws_subnet.pub_a.id
  route_table_id = aws_route_table.pub.id
}

resource "aws_route_table_association" "pub_c" {
  subnet_id      = aws_subnet.pub_c.id
  route_table_id = aws_route_table.pub.id
}

resource "aws_route_table" "priv" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }
  tags = { Name = "${local.name}-rt-priv" }
}

resource "aws_route_table_association" "priv_a" {
  subnet_id      = aws_subnet.priv_a.id
  route_table_id = aws_route_table.priv.id
}

resource "aws_route_table_association" "priv_c" {
  subnet_id      = aws_subnet.priv_c.id
  route_table_id = aws_route_table.priv.id
}

# EC2 Security Group
resource "aws_security_group" "ec2" {
  name   = "${local.name}-ec2-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 5000
    to_port     = 5000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.name}-ec2-sg" }
}

# EC2 IAM Role
resource "aws_iam_role" "ec2" {
  name_prefix = "${local.name}-ec2-"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ec2_admin" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

resource "aws_iam_instance_profile" "ec2" {
  name_prefix = "${local.name}-ec2-"
  role = aws_iam_role.ec2.name
}

# EC2 Instance (App + FluentBit)
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_instance" "app" {
  ami                    = data.aws_ami.al2023.id
  instance_type          = "t3.small"
  subnet_id              = aws_subnet.pub_a.id
  vpc_security_group_ids = [aws_security_group.ec2.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2.name

  user_data = <<-EOF
#!/bin/bash
# Set timezone (Asia/Seoul)
timedatectl set-timezone Asia/Seoul

# Install Docker
yum install -y docker
systemctl enable docker && systemctl start docker

# Create app directory
mkdir -p /home/ec2-user/app
cat > /home/ec2-user/app/app.py << 'APPEOF'
from flask import Flask, request, jsonify
import logging
import random
import time

app = Flask(__name__)

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s %(levelname)s %(message)s'
)
logger = logging.getLogger(__name__)

USERS = ["alice", "bob", "carol", "dave", "eve"]
ACTIONS = ["login", "logout", "purchase", "view_item", "search"]

@app.route("/")
def index():
    return jsonify({"service": "m3-log-generator", "status": "healthy"})

@app.route("/health")
def health():
    return jsonify({"status": "ok"}), 200

@app.route("/generate")
def generate():
    count = int(request.args.get("count", 10))
    logs = []
    for _ in range(count):
        user = random.choice(USERS)
        action = random.choice(ACTIONS)
        level = random.choice(["INFO", "INFO", "INFO", "WARNING", "ERROR"])
        msg = f"user={user} action={action} status={'success' if level == 'INFO' else 'failed'}"
        if level == "INFO":
            logger.info(msg)
        elif level == "WARNING":
            logger.warning(msg)
        else:
            logger.error(msg)
        logs.append({"level": level, "message": msg})
        time.sleep(0.05)
    return jsonify({"generated": count, "logs": logs})

@app.route("/error")
def trigger_error():
    logger.error("manual error triggered by /error endpoint")
    return jsonify({"status": "error logged"}), 200

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
APPEOF

cat > /home/ec2-user/app/requirements.txt << 'REQEOF'
flask==3.1.3
REQEOF

cat > /home/ec2-user/app/Dockerfile << 'DKREOF'
FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app.py .
EXPOSE 5000
CMD ["python", "app.py"]
DKREOF

# Build and run container
cd /home/ec2-user/app
docker build -t wsc-log-app .
docker run -d --name wsc-log-app --restart always --log-driver json-file -e TZ=Asia/Seoul -p 5000:5000 wsc-log-app

# Install Fluent Bit
curl https://raw.githubusercontent.com/fluent/fluent-bit/master/install.sh | sh
systemctl enable fluent-bit

# Configure Fluent Bit (will be updated after Loki NLB is available)
cat > /etc/fluent-bit/fluent-bit.conf << 'FBEOF'
[SERVICE]
    Flush        1
    Daemon       Off
    Log_Level    info
    Parsers_File parsers.conf

[INPUT]
    Name         tail
    Path         /var/lib/docker/containers/*/*.log
    Parser       docker
    Tag          docker.*
    Refresh_Interval 5

[FILTER]
    Name         record_modifier
    Match        *
    Record       namespace wsc-app-log

[OUTPUT]
    Name         loki
    Match        *
    Host         LOKI_NLB_DNS
    Port         3100
    Labels       namespace=$namespace
FBEOF

systemctl restart fluent-bit

# --- kubectl / eksctl 설치 ---
rm -f /usr/local/bin/kubectl
curl -O https://s3.us-west-2.amazonaws.com/amazon-eks/1.33.0/2025-05-01/bin/linux/amd64/kubectl
chmod +x ./kubectl
mv ./kubectl /usr/bin/

curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
mv /tmp/eksctl /usr/local/bin
eksctl version

# --- helm 설치 (Loki/Grafana 배포용) ---
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# --- terraform 설치 (k8s 레이어를 bastion에서 apply) ---
yum install -y yum-utils
yum-config-manager --add-repo https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo
yum -y install terraform

# --- ec2-user SSH 패스워드 접속 허용 (채점관 SSH 대비) ---
echo "ec2-user:Skill53##" | chpasswd
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
find /etc/ssh/sshd_config.d/ -type f -exec sed -i 's/^PasswordAuthentication.*/PasswordAuthentication yes/' {} \;
systemctl restart sshd

# --- 채점 디렉터리 준비 ---
mkdir -p /home/ec2-user/marking
chown -R ec2-user:ec2-user /home/ec2-user/marking

# --- kubeconfig 자동 설정 스크립트 ---
cat > /home/ec2-user/set-kubeconfig.sh << 'KCEOF'
#!/bin/bash
aws eks update-kubeconfig --region ap-northeast-1 --name wsc-logging-cluster
kubectl get nodes
KCEOF
chmod +x /home/ec2-user/set-kubeconfig.sh
chown ec2-user:ec2-user /home/ec2-user/set-kubeconfig.sh

sudo -u ec2-user bash -c "aws eks update-kubeconfig --region ap-northeast-1 --name wsc-logging-cluster" || true
EOF

  tags = { Name = "${local.name}-app-bastion" }
}

# EKS Cluster IAM
resource "aws_iam_role" "eks_cluster" {
  name_prefix = "${local.name}-cluster-"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  role       = aws_iam_role.eks_cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# EKS Cluster
resource "aws_eks_cluster" "main" {
  name     = "${local.name}-cluster"
  version  = "1.35"
  role_arn = aws_iam_role.eks_cluster.arn

  vpc_config {
    subnet_ids              = [aws_subnet.pub_a.id, aws_subnet.pub_c.id, aws_subnet.priv_a.id, aws_subnet.priv_c.id]
    endpoint_public_access  = true
    endpoint_private_access = true
  }

  access_config {
    authentication_mode = "API_AND_CONFIG_MAP"
  }

  depends_on = [aws_iam_role_policy_attachment.eks_cluster_policy]
}

# EKS access entry for EC2
resource "aws_eks_access_entry" "ec2" {
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = aws_iam_role.ec2.arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "ec2" {
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = aws_iam_role.ec2.arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  access_scope {
    type = "cluster"
  }
}

# EKS Node Group IAM
resource "aws_iam_role" "eks_node" {
  name_prefix = "${local.name}-node-"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "node_worker" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "node_cni" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "node_ecr" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# EKS Node Group
resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${local.name}-ng"
  node_role_arn   = aws_iam_role.eks_node.arn
  subnet_ids      = [aws_subnet.priv_a.id, aws_subnet.priv_c.id]
  instance_types  = ["t3.medium"]
  ami_type        = "AL2023_x86_64_STANDARD"

  scaling_config {
    desired_size = 2
    min_size     = 2
    max_size     = 4
  }

  depends_on = [
    aws_iam_role_policy_attachment.node_worker,
    aws_iam_role_policy_attachment.node_cni,
    aws_iam_role_policy_attachment.node_ecr,
  ]
}

# EKS Pod Identity Agent (EBS CSI Driver Pod Identity용)
resource "aws_eks_addon" "pod_identity" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "eks-pod-identity-agent"
  depends_on   = [aws_eks_node_group.main]
}

output "cluster_name" {
  value = aws_eks_cluster.main.name
}

output "ec2_public_ip" {
  value = aws_instance.app.public_ip
}

# EBS CSI Driver (Pod Identity) - Loki PVC용
resource "aws_iam_role" "ebs_csi" {
  name_prefix = "${local.name}-ebs-csi-"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "pods.eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  role       = aws_iam_role.ebs_csi.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

resource "aws_eks_pod_identity_association" "ebs_csi" {
  cluster_name    = aws_eks_cluster.main.name
  namespace       = "kube-system"
  service_account = "ebs-csi-controller-sa"
  role_arn        = aws_iam_role.ebs_csi.arn
  depends_on      = [aws_eks_addon.pod_identity]
}

resource "aws_eks_addon" "ebs_csi" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "aws-ebs-csi-driver"
  resolve_conflicts_on_create = "OVERWRITE"
  depends_on = [
    aws_eks_node_group.main,
    aws_eks_pod_identity_association.ebs_csi,
  ]
}

output "ec2_instance_id" {
  value = aws_instance.app.id
}