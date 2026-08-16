# Copyright (c) 2026 Giancarlo Martinez
# SPDX-License-Identifier: Apache-2.0
variable "site_bucket_name" {
  description = "This is the name of the bucket that will host your web app"
  type        = string
}


variable "site_bucket_regional_domain_name" {
  type        = string
  description = "REST endpoint host of the site bucket (bucket.s3.<region>.amazonaws.com). From modules/s3Site. Must NOT be the s3-website-* endpoint - OAC cannot sign to one."

  validation {
    condition     = !can(regex("s3-website", var.site_bucket_regional_domain_name))
    error_message = "This is the website endpoint. OAC requires the REST endpoint - pass bucket_regional_domain_name."
  }
}

variable "site_bucket_arn" {
  description = "ARN of bucket that hosts the site"
  type        = string
}