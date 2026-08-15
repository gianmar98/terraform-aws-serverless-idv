# Copyright (c) 2026 Giancarlo Martinez
# SPDX-License-Identifier: Apache-2.0

# Project-wide ----------------------------------------------------------------------
variable "project_region" {
  description = "AWS region the project deploys to"
  type        = string
}

variable "project_environment" {
  description = "Environment name (e.g., dev, prod) — used in default_tags"
  type        = string

  # Stamped onto every resource name via local.env_suffix, so a typo silently
  # builds a parallel stack of misnamed resources rather than failing.
  validation {
    condition     = contains(["dev", "prod"], var.project_environment)
    error_message = "project_environment must be dev or prod."
  }
}

variable "project_name" {
  description = "Project name — used in default_tags"
  type        = string
}

variable "project_owner" {
  description = "Owner — used in default_tags"
  type        = string
}

# S3 ---------------------------------------------------------------------------------
variable "document_s3_bucket_name" {
  description = "Name of the document S3 bucket"
  type        = string
}

variable "document_retention_days" {
  description = "Days after upload that identity documents (zipped/ and unzipped/) are expired"
  type        = number
}


# Lambda -------------------------------------------------------------------------
variable "document_lambda_role_name" {
  description = "Name of the Lambda execution role"
  type        = string
}

variable "document_lambda_policy_name" {
  description = "Name of the inline policy attached to the Lambda execution role"
  type        = string
}

variable "lambda_cloudwatch_logs_policy_name" {
  description = "Name of the CloudWatch Logs Policy"
  type        = string
}

variable "document_lambda_function_name" {
  description = "Name of the document Lambda function"
  type        = string
}

variable "lambda_functions_timeout" {
  description = "The max mount of time function should run for"
  type        = number
}

variable "lambda_rekognition_face_comparison_policy_name" {
  description = "This will be the name of the managed policy so lambda can compare faces"
  type        = string
}

variable "lambda_textract_analyze_id_policy_name" {
  description = "This will be the name of the managed policy so Textract can analyze ID"
  type        = string
}

variable "validate_lambda_function_name" {
  description = "This is the name for my Lambda function to validate my documents"
  type        = string
}

variable "validate_lambda_role_name" {
  description = "This is the name of the Role of my validation lambda function"
  type        = string
}

variable "validation_lambda_cloudwatch_logs_policy_name" {
  description = "Name of the CloudWatch Logs Policy for my Validation Lambda"
  type        = string
}

variable "submit_license_lambda_function_name" {
  description = "This is the name for my Lambda function to validate my documents"
  type        = string
}

variable "submit_license_lambda_role_name" {
  description = "This is the name of the Role of my validation lambda function"
  type        = string
}

variable "submit_license_lambda_cloudwatch_logs_policy_name" {
  description = "Name of the CloudWatch Logs Policy for my Validation Lambda"
  type        = string
}

variable "sqs_submit_license_policy_name" {
  description = "This is the name of the policy that allows SQS to invoke lambda"
  type        = string
}

variable "submit_license_lambda_policy_name" {
  description = "Name of the inline policy attached to the Lambda execution role"
  type        = string
}

variable "unzip_lambda_function_name" {
  description = "Name of the lambda function to unzip the file and extract the app_uuid"
  type        = string
}

variable "unzip_lambda_function_role_name" {
  description = "Name of the role being assumed by the Lambda function that will unzip the license file"
  type        = string
}

variable "unzip_license_lambda_cloudwatch_logs_policy_name" {
  description = "Name of the policy so unzip license lambda can send logs to cloudwatch"
  type        = string
}

# WRITE TO DYNAMO lambda function
variable "write_to_dynamo_lambda_function_name" {
  description = "Name of the lambda function that will write to the lambda function after receiving the app_uuid from the unzip lambda function"
}

variable "write_to_dynamo_lambda_function_role_name" {
  description = "name of the role the lambda function that writes to DynamoDB would assume"
  type        = string
}

variable "write_to_dynamo_lambda_cloudwatch_logs_policy_name" {
  description = "name of the cloudwatch logs policy for the write to dynamoDB lambda function"
  type        = string
}

# COMPARE FACES lambda function
variable "compare_faces_lambda_function_name" {
  description = "Name of the lambda function that will compare the user face and the license"
  type        = string
}

variable "compare_faces_lambda_function_role_name" {
  description = "name of the role the lambda function that compares faces would assume"
  type        = string
}

variable "compare_faces_lambda_cloudwatch_logs_policy_name" {
  description = "name of the cloudwatch logs policy for the compare faceslambda function"
  type        = string
}

variable "compare_faces_lambda_policy_name" {
  description = "Name of the inline policy attached to the Lambda execution role"
  type        = string
}

#COMPARE DETAILS lambda function
variable "compare_details_lambda_function_name" {
  description = "This is the name of the lambda function to compare the details of the results. is the 4th function."
  type        = string
}

variable "compare_details_lambda_function_role_name" {
  description = "name of the role the lambda function that compares details of the comparisons. 4th lambda."
  type        = string
}

variable "compare_details_lambda_cloudwatch_logs_policy_name" {
  description = "name of the cloudwatch logs policy for the compare details lambda function"
  type        = string
}

variable "compare_details_lambda_policy_name" {
  description = "Name of the inline policy attached to the Lambda execution role"
  type        = string
}

#APP API lambda function
variable "app_api_lambda_function_name" {
  description = "Name of the browser-facing app API lambda function. Not part of the document pipeline."
  type        = string
}
variable "app_api_lambda_function_role_name" {
  description = "Name of the role for the lambda function serving the browser's upload-url and status calls"
  type        = string
}
variable "app_api_lambda_cloudwatch_logs_policy_name" {
  description = "name of the cloudwatch logs policy for the app API lambda function"
  type        = string
}
variable "app_api_lambda_policy_name" {
  description = "Name of the inline policy attached to the Lambda execution role"
  type        = string
}

# DynamoDB ---------------------------------------------------------------------------
variable "customer_metadata_dynamo_db_table_name" {
  description = "Name of the customer metadata DynamoDB table"
  type        = string
}

variable "customer_metadata_table_hash_partition_key" {
  description = "Hash/Partition key of the customer metadata table"
  type        = string
}

variable "customer_metadata_table_class" {
  description = "Storage class for the customer metadata DynamoDB table"
  type        = string
  default     = "STANDARD"
}

variable "customer_metadata_table_RCU" {
  description = "Read Capacity Units"
  type        = number
}

variable "customer_metadata_table_WCU" {
  description = "Write Capacity Units"
  type        = number
}

variable "customer_metadata_table_autoscaling_enabled" {
  description = "Enable autoscaling on the customer metadata table"
  type        = bool
}

variable "customer_metadata_table_pitr_enabled" {
  description = "Enable point-in-time recovery on the customer metadata table"
  type        = bool
}

variable "customer_metadata_table_deletion_protection" {
  description = "Block DeleteTable on the customer metadata table"
  type        = bool
}

variable "customer_metadata_table_min_RWcapacity" {
  description = "Minimum autoscaling capacity"
  type        = number
}

variable "customer_metadata_table_max_RWcapacity" {
  description = "Maximum autoscaling capacity"
  type        = number
}

variable "customer_metadata_table_target_scaling_val" {
  description = "Target % of provisioned capacity to trigger autoscaling"
  type        = number
}

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
  description = "Email subscribed to the SNS topic"
  type        = string
}

# API GATEWAY ----
variable "validate_api_gw_name" {
  description = "This is the name of the API GW that will trigger the validation Lambda"
  type        = string
}

# SQS ------------
variable "sqs_queue_name" {
  description = "This is the name of the SQS queue"
  type        = string
}

variable "sqs_dlq_name" {
  description = "This is the name of the SQS DLQ"
  type        = string
}

# STEP FUNCTION ------------
variable "document_state_machine_name" {
  description = "This is the name of the Document State Machine that orchestrates all 4 lambda functions (Unzip -> Write to Dynamo -> [Parallel] Compare Faces & Compare Details -> SQS Queue)"
  type        = string
}
variable "document_state_machine_iam_role_name" {
  description = "This is the name of the IAM role the Document Step Function will assume"
  type        = string
}


# COGNITO -------------
variable "cognito_user_pool_name" {
  description = "This is the name of the authentication user pool from cognito"
  type        = string
}
variable "cognito_user_pool_client_name" {
  description = "This is the name of the authentication user pool from cognito"
  type        = string
}
variable "seed_users" {
  description = "Demo logins for the dev Cognito pool, as email => password."
  type        = map(string)
  sensitive   = true
}


# CORS -------------
variable "cors_max_age_seconds" {
  description = "How long a browser may cache the CORS preflight (OPTIONS) response. Shared by the document bucket and the HTTP API."
  type        = number
}

#S3 Site Hosting Bucket
variable "site_bucket_name" {
  description = "This is the name of the bucket that will host your web app"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.site_bucket_name))
    error_message = "Bucket name must be 3-63 characters: lowercase letters, digits, dots or hyphens, starting and ending alphanumeric."
  }

}
