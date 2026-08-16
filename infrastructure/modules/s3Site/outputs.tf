# Copyright (c) 2026 Giancarlo Martinez
# SPDX-License-Identifier: Apache-2.0

output "site_bucket_name" {
  description = "Name/ID of the site bucket"
  value       = aws_s3_bucket.site.id
}

output "site_website_endpoint" {
  description = "Website endpoint host URL"
  value       = aws_s3_bucket_website_configuration.site.website_endpoint
}

output "site_website_url" {
  description = "Full URL of the s3 endpoint of the site"
  value       = "http://${aws_s3_bucket_website_configuration.site.website_endpoint}"
}

output "site_bucket_arn" {
  description = "ARN of bucket that hosts the site"
  value       = aws_s3_bucket.site.arn
}

output "site_bucket_regional_domain_name" {
  description = "regional domain name of bucket that hosts the site"
  value       = aws_s3_bucket.site.bucket_regional_domain_name
}