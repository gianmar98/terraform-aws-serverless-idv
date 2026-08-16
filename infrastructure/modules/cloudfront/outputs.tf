# Copyright (c) 2026 Giancarlo Martinez
# SPDX-License-Identifier: Apache-2.0

output "cloudfront_domain_name" {
  description = "Public domain of the distribution, no scheme (open https:// + this in a browser)."
  value       = aws_cloudfront_distribution.cdn.domain_name
}

output "cloudfront_distribution_id" {
  description = "Distribution ID that is needed by the deploy step's cache invalidation."
  value       = aws_cloudfront_distribution.cdn.id
}

output "cloudfront_url" {
  description = "Full HTTPS URL of the site."
  value       = "https://${aws_cloudfront_distribution.cdn.domain_name}"
}