resource "aws_dynamodb_table" "main" {
  name           = var.table_name
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "sensor_id"
  range_key      = "timestamp"
  stream_enabled = var.enable_global_table
  stream_view_type = var.enable_global_table ? "NEW_AND_OLD_IMAGES" : null
  
  attribute {
    name = "sensor_id"
    type = "S"
  }
  
  attribute {
    name = "timestamp"
    type = "S"
  }
  
  attribute {
    name = "sensor_type"
    type = "S"
  }
  
  global_secondary_index {
    name            = "sensor_type-timestamp-index"
    hash_key        = "sensor_type"
    range_key       = "timestamp"
    projection_type = "ALL"
  }
  
  ttl {
    attribute_name = "ttl"
    enabled        = true
  }
  
  point_in_time_recovery {
    enabled = true
  }
  
  server_side_encryption {
    enabled = true
  }
}

output "table_name" {
  value = aws_dynamodb_table.main.name
}

output "table_arn" {
  value = aws_dynamodb_table.main.arn
}
