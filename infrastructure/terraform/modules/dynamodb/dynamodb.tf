# DynamoDB Module
# Creates DynamoDB table for processed sensor metrics with GSI and TTL

# DynamoDB table with on-demand billing
resource "aws_dynamodb_table" "main" {
  name           = var.table_name
  billing_mode   = "PAY_PER_REQUEST"  # Auto-scaling based on usage
  hash_key       = "sensor_id"
  range_key      = "timestamp"
  stream_enabled = var.enable_global_table
  stream_view_type = var.enable_global_table ? "NEW_AND_OLD_IMAGES" : null
  
  # Primary key attributes
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
  
  # GSI for querying by sensor type
  global_secondary_index {
    name            = "sensor_type-timestamp-index"
    hash_key        = "sensor_type"
    range_key       = "timestamp"
    projection_type = "ALL"
  }
  
  # Auto-delete old records based on TTL attribute
  ttl {
    attribute_name = "ttl"
    enabled        = true
  }
  
  # Enable point-in-time recovery for data protection
  point_in_time_recovery {
    enabled = true
  }
  
  # Encrypt data at rest
  server_side_encryption {
    enabled = true
  }
}
