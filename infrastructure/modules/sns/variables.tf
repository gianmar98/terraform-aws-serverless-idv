# Copyright (c) 2026 Giancarlo Martinez
# SPDX-License-Identifier: Apache-2.0

# SNS --------------------------------------------------------------------------------
variable "app_notification_sns_name" {
  description = "Name of the application notifications SNS topic"
  type        = string
}

variable "app_notification_kms_key" {
  description = "KMS master key id/alias used to encrypt the SNS topic"
  type        = string
}

variable "app_notification_email_endpoint" {
  description = "Email address subscribed to the SNS topic (requires manual confirmation)"
  type        = string

  # A malformed address still applies cleanly — the subscription is created but can
  # never be confirmed, so every alert is silently dropped.
  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.app_notification_email_endpoint))
    error_message = "app_notification_email_endpoint must be a valid email address."
  }
}