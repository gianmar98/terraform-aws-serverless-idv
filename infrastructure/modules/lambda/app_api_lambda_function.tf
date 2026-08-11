# Copyright (c) 2026 Giancarlo Martinez
# SPDX-License-Identifier: Apache-2.0

# Package the Lambda function code
data "archive_file" "app_api_lambda_function_archive_file" {
  type        = "zip"
  source_file = "${path.module}/src/app_api_lambda.py"
  output_path = "${path.module}/build/app_api_lambda.zip"
}

# Lambda function
resource "aws_lambda_function" "app_api_lambda_function" {
  description   = "Browser-facing API: mints presigned S3 PUT URLs and reads submission status"
  filename      = data.archive_file.app_api_lambda_function_archive_file.output_path
  function_name = var.app_api_lambda_function_name
  role          = aws_iam_role.app_api_lambda_role.arn
  handler       = "app_api_lambda.lambda_handler"

  #Hash being shipped. If this value differs from the original one, treat the function as changed and redeploy it.
  source_code_hash = data.archive_file.app_api_lambda_function_archive_file.output_base64sha256

  runtime = "python3.13"
  timeout = var.lambda_functions_timeout

  logging_config {
    log_group  = aws_cloudwatch_log_group.app_api_lambda_logs.name
    log_format = "Text"
  }

  # This function publishes nothing and consumes nothing.
  environment {
    variables = {
      BUCKET = var.document_s3_bucket_name
      TABLE  = var.dynamodb_document_table_name
    }
  }
}

# API Gateway invokes this function, so the matching