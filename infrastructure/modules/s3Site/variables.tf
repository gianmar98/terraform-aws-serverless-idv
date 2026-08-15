# Copyright (c) 2026 Giancarlo Martinez
# SPDX-License-Identifier: Apache-2.0

variable "site_bucket_name" {
  description = "This is the name of the bucket that will host your web app"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.site_bucket_name))
    error_message = "Bucket name must be 3-63 characters: lowercase letters, digits, dots or hyphens, starting and ending alphanumeric."
  }

}
