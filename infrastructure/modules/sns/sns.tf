# Copyright (c) 2026 Giancarlo Martinez
# SPDX-License-Identifier: Apache-2.0

module "app_notification_sns" {
  source  = "terraform-aws-modules/sns/aws"
  version = "7.1.0"

  name = var.app_notification_sns_name

  kms_master_key_id = var.app_notification_kms_key
  # kms_master_key_id = ""
  #The ID of an AWS-managed customer master key (CMK) for Amazon SNS or a custom CMK
}

resource "aws_sns_topic_subscription" "personal_email_notification" {
  endpoint  = var.app_notification_email_endpoint
  protocol  = "email"
  topic_arn = module.app_notification_sns.topic_arn
}