# =============================================================================
# VPC (Reference01)
#  - wsc-vpc 10.0.0.0/16
#  - public-a/c (10.0.0.0/24, 10.0.1.0/24)  -> wsc-public-rtb (IGW)
#  - private-a/c (10.0.2.0/24, 10.0.3.0/24) -> wsc-private-a/c-rtb (NAT)
#  - workload-a/c (10.0.4.0/24, 10.0.5.0/24)-> wsc-workload-a/c-rtb (No Internet, 라우트 없음)
# =============================================================================

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "wsc-vpc"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "wsc-igw" }
}

# ---- 서브넷 ----
resource "aws_subnet" "this" {
  for_each = local.subnets

  vpc_id            = aws_vpc.main.id
  cidr_block        = each.value.cidr
  availability_zone = each.value.az

  # public 서브넷만 퍼블릭 IP 자동 할당
  map_public_ip_on_launch = startswith(each.key, "public")

  tags = merge(
    { Name = each.value.name },
    # ALB Controller 서브넷 자동 발견용 태그
    startswith(each.key, "public") ? { "kubernetes.io/role/elb" = "1" } : {},
    startswith(each.key, "private") ? { "kubernetes.io/role/internal-elb" = "1" } : {},
    startswith(each.key, "workload") ? { "kubernetes.io/cluster/wsc-eks-cluster" = "shared" } : {},
  )
}

# ---- EIP + NAT Gateway (AZ별 1개씩, public 서브넷에 배치) ----
resource "aws_eip" "nat" {
  for_each = toset(["a", "c"])
  domain   = "vpc"
  tags     = { Name = "wsc-nat-eip-${each.key}" }
}

resource "aws_nat_gateway" "this" {
  for_each      = toset(["a", "c"])
  allocation_id = aws_eip.nat[each.key].id
  subnet_id     = aws_subnet.this["public_${each.key}"].id
  tags          = { Name = "wsc-nat-${each.key}" }

  depends_on = [aws_internet_gateway.main]
}

# ---- Public Route Table (IGW) ----
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "wsc-public-rtb" }
}

resource "aws_route" "public_igw" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}

resource "aws_route_table_association" "public" {
  for_each       = toset(["a", "c"])
  subnet_id      = aws_subnet.this["public_${each.key}"].id
  route_table_id = aws_route_table.public.id
}

# ---- Private Route Tables (NAT, AZ별) ----
resource "aws_route_table" "private" {
  for_each = toset(["a", "c"])
  vpc_id   = aws_vpc.main.id
  tags     = { Name = "wsc-private-${each.key}-rtb" }
}

resource "aws_route" "private_nat" {
  for_each               = toset(["a", "c"])
  route_table_id         = aws_route_table.private[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[each.key].id
}

resource "aws_route_table_association" "private" {
  for_each       = toset(["a", "c"])
  subnet_id      = aws_subnet.this["private_${each.key}"].id
  route_table_id = aws_route_table.private[each.key].id
}

# ---- Workload Route Tables (No Internet, 라우트 없음 - local 만) ----
resource "aws_route_table" "workload" {
  for_each = toset(["a", "c"])
  vpc_id   = aws_vpc.main.id
  tags     = { Name = "wsc-workload-${each.key}-rtb" }
}

resource "aws_route_table_association" "workload" {
  for_each       = toset(["a", "c"])
  subnet_id      = aws_subnet.this["workload_${each.key}"].id
  route_table_id = aws_route_table.workload[each.key].id
}
