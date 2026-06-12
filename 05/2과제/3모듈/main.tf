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
  tags = { Name = "${local.name}-vpc" }
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
  name = "${local.name}-ec2-role"
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
  name = "${local.name}-ec2-profile"
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
docker run -d --name wsc-log-app --restart always --log-driver json-file -p 5000:5000 wsc-log-app

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
EOF

  tags = { Name = "${local.name}-app-bastion" }
}

# EKS Cluster IAM
resource "aws_iam_role" "eks_cluster" {
  name = "${local.name}-cluster-role"
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
  name = "${local.name}-node-role"
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

output "cluster_name" {
  value = aws_eks_cluster.main.name
}

output "ec2_public_ip" {
  value = aws_instance.app.public_ip
}
