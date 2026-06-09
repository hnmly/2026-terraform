# =============================================================================
# DynamoDB (wsc-table) - Customer Managed Key 암호화, PK client_id
# =============================================================================

resource "aws_dynamodb_table" "table" {
  name         = "wsc-table"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "client_id"

  attribute {
    name = "client_id"
    type = "S"
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.main.arn
  }

  tags = { Name = "wsc-table" }
}
