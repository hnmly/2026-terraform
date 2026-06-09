# =============================================================================
# Bastion (EKS 접근 및 채점용)
#  - Public Subnet, EIP(고정 IP), SSH Password(Skill53##), Admin 권한
#  - 패키지: awscliv2, jq, curl, ping, kubectl, eksctl
# =============================================================================

resource "aws_security_group" "bastion" {
  name        = "wsc-bastion-sg"
  description = "Bastion - allow SSH only inbound"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH from anywhere"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "wsc-bastion-sg" }
}

# ---- Admin 권한 IAM Role / Instance Profile ----
data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "bastion" {
  name_prefix        = "wsc-bastion-role-"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
  tags               = { Name = "wsc-bastion-role" }
}

resource "aws_iam_role_policy_attachment" "bastion_admin" {
  role       = aws_iam_role.bastion.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/AdministratorAccess"
}

resource "aws_iam_instance_profile" "bastion" {
  name_prefix = "wsc-bastion-profile-"
  role        = aws_iam_role.bastion.name
}

# ---- Bastion EC2 ----
resource "aws_instance" "bastion" {
  ami                    = data.aws_ssm_parameter.al2023.value
  instance_type          = var.bastion_instance_type
  subnet_id              = aws_subnet.this["public_a"].id
  vpc_security_group_ids = [aws_security_group.bastion.id]
  iam_instance_profile   = aws_iam_instance_profile.bastion.name

  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }

  user_data = <<-EOF
    #!/bin/bash
    set -x
    # SSH 패스워드 인증 활성화 + ec2-user 패스워드 설정
    echo "ec2-user:${var.ssh_password}" | chpasswd
    sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
    mkdir -p /etc/ssh/sshd_config.d
    echo "PasswordAuthentication yes" > /etc/ssh/sshd_config.d/60-wsc.conf
    systemctl restart sshd

    # 패키지 설치
    dnf install -y jq tar iputils unzip git
    # awscli v2
    curl -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
    cd /tmp && unzip -q awscliv2.zip && ./aws/install --update
    # kubectl
    curl -sLO "https://dl.k8s.io/release/v1.32.0/bin/linux/amd64/kubectl"
    install -m 0755 kubectl /usr/local/bin/kubectl
    # eksctl
    curl -sL "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_Linux_amd64.tar.gz" | tar xz -C /tmp
    install -m 0755 /tmp/eksctl /usr/local/bin/eksctl
    # helm
    curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
  EOF

  user_data_replace_on_change = true

  tags = { Name = "wsc-bastion" }
}

resource "aws_eip" "bastion" {
  instance = aws_instance.bastion.id
  domain   = "vpc"
  tags     = { Name = "wsc-bastion-eip" }
}
