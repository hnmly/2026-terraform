resource "aws_security_group" "alb" {
  name        = "skills-book-alb-sg"
  vpc_id      = aws_vpc.main.id
  description = "ALB Security Group"

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "skills-book-alb-sg" }
}

resource "aws_security_group" "ecs" {
  name        = "skills-book-ecs-sg"
  vpc_id      = aws_vpc.main.id
  description = "ECS Tasks Security Group"

  ingress {
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "skills-book-ecs-sg" }
}
