# Copyright (c) 2026 Giancarlo Martinez
# SPDX-License-Identifier: Apache-2.0

# DynamoDB ---------------------------------------------------------------------------
output "customer_metadata_table_name" {
  description = "Name of the CustomerMetadata DynamoDB table"
  value       = module.customer_metadata_table.dynamodb_table_id
}

output "customer_metadata_table_arn" {
  description = "ARN of the CustomerMetadata DynamoDB table"
  value       = module.customer_metadata_table.dynamodb_table_arn
}
