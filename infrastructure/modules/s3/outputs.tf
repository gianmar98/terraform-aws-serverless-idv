# Copyright (c) 2026 Giancarlo Martinez
# SPDX-License-Identifier: Apache-2.0

# S3 ---------------------------------------------------------------------------------
output "document_bucket_name" {
  description = "Name (ID) of the document S3 bucket"
  value       = module.document_s3_bucket.s3_bucket_id
}

output "document_bucket_arn" {
  description = "ARN of the document S3 bucket"
  value       = module.document_s3_bucket.s3_bucket_arn
}

output "document_bucket_regional_domain_name" {
  description = "Regional domain name of the document S3 bucket"
  value       = module.document_s3_bucket.s3_bucket_bucket_regional_domain_name
}

output "document_bucket_id" {
  description = "ID of the document bucket"
  value       = module.document_s3_bucket.s3_bucket_id
}

# KMS ---------------------------------------------------------------------------------
output "document_kms_key_arn" {
  description = "ARN of the CMK encrypting the document bucket — every role that reads or writes objects needs kms:Decrypt (and kms:GenerateDataKey to write) on this"
  value       = aws_kms_key.document_key.arn
}
