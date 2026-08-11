# Copyright (c) 2026 Giancarlo Martinez
# SPDX-License-Identifier: Apache-2.0


# SNS --------------------------------------------------------------------------------
output "sns_topic_arn" {
  description = "ARN of the application notifications SNS topic"
  value       = module.app_notification_sns.topic_arn
}

output "sns_topic_name" {
  description = "Name of the application notifications SNS topic"
  value       = module.app_notification_sns.topic_name
}