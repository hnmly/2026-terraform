data "aws_partition" "current" {}

# Amazon Linux 2023 (x86_64) AMI - Bastion OS
data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

locals {
  partition = data.aws_partition.current.partition

  subnets = {
    public_a   = { cidr = "10.0.0.0/24", az = var.azs[0], name = "wsc-public-a" }
    public_c   = { cidr = "10.0.1.0/24", az = var.azs[1], name = "wsc-public-c" }
    private_a  = { cidr = "10.0.2.0/24", az = var.azs[0], name = "wsc-private-a" }
    private_c  = { cidr = "10.0.3.0/24", az = var.azs[1], name = "wsc-private-c" }
    workload_a = { cidr = "10.0.4.0/24", az = var.azs[0], name = "wsc-workload-a" }
    workload_c = { cidr = "10.0.5.0/24", az = var.azs[1], name = "wsc-workload-c" }
  }
}
