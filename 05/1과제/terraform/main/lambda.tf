# =============================================================================
# Lambda (wsc-get-table-function)  - Private Subnet, GET /v1/book
#  - CloudFront -> ALB -> (Lambda Target Group) 경로로 호출
# =============================================================================

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda" {
  name_prefix        = "wsc-get-table-function-role-"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role_policy_attachment" "lambda_vpc" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

data "aws_iam_policy_document" "lambda" {
  statement {
    sid       = "DynamoDB"
    actions   = ["dynamodb:GetItem", "dynamodb:Query"]
    resources = [aws_dynamodb_table.table.arn]
  }
  statement {
    sid       = "KMS"
    actions   = ["kms:Decrypt", "kms:DescribeKey"]
    resources = [aws_kms_key.main.arn]
  }
}

resource "aws_iam_role_policy" "lambda" {
  name   = "wsc-lambda-dynamodb"
  role   = aws_iam_role.lambda.id
  policy = data.aws_iam_policy_document.lambda.json
}

# Lambda 전용 보안그룹
resource "aws_security_group" "lambda" {
  name        = "wsc-lambda-sg"
  description = "Lambda ENI SG"
  vpc_id      = local.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "wsc-lambda-sg" }
}

data "archive_file" "lambda" {
  type        = "zip"
  source_file = "${path.module}/lambda/lambda_function.py"
  output_path = "${path.module}/build/lambda.zip"
}

resource "aws_lambda_function" "get_table" {
  function_name    = "wsc-get-table-function"
  role             = aws_iam_role.lambda.arn
  runtime          = "python3.13"
  handler          = "lambda_function.lambda_handler"
  timeout          = 30
  filename         = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.table.name
    }
  }

  vpc_config {
    subnet_ids = [
      local.subnet_ids["wsc-private-a"],
      local.subnet_ids["wsc-private-c"],
    ]
    security_group_ids = [aws_security_group.lambda.id]
  }

  tags = { Name = "wsc-get-table-function" }

  depends_on = [aws_iam_role_policy_attachment.lambda_vpc]
}

# ALB가 Lambda를 호출할 수 있도록 권한 부여 (Ingress가 Lambda 대상으로 라우팅)
resource "aws_lambda_permission" "alb" {
  statement_id  = "AllowALBInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.get_table.function_name
  principal     = "elasticloadbalancing.amazonaws.com"
}