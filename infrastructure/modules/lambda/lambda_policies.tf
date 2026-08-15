# Copyright (c) 2026 Giancarlo Martinez
# SPDX-License-Identifier: Apache-2.0

locals {
  log_group_name        = "/aws/lambda/${var.document_lambda_function_name}"
  logs_group_create_arn = "arn:aws:logs:${var.current_region}:${var.current_account_id}:*"
  log_stream_arn_prefix = "arn:aws:logs:${var.current_region}:${var.current_account_id}:log-group:${local.log_group_name}:*"

  validation_log_group_name        = "/aws/lambda/${var.validate_lambda_function_name}"
  validation_logs_group_create_arn = "arn:aws:logs:${var.current_region}:${var.current_account_id}:*"
  validation_log_stream_arn_prefix = "arn:aws:logs:${var.current_region}:${var.current_account_id}:log-group:${local.validation_log_group_name}:*"

  submit_license_log_group_name        = "/aws/lambda/${var.submit_license_lambda_function_name}"
  submit_license_logs_group_create_arn = "arn:aws:logs:${var.current_region}:${var.current_account_id}:*"
  submit_license_log_stream_arn_prefix = "arn:aws:logs:${var.current_region}:${var.current_account_id}:log-group:${local.submit_license_log_group_name}:*"

  unzip_license_log_group_name        = "/aws/lambda/${var.unzip_lambda_function_name}"
  unzip_license_logs_group_create_arn = "arn:aws:logs:${var.current_region}:${var.current_account_id}:*"
  unzip_license_log_stream_arn_prefix = "arn:aws:logs:${var.current_region}:${var.current_account_id}:log-group:${local.unzip_license_log_group_name}:*"

  write_to_dynamo_log_group_name        = "/aws/lambda/${var.write_to_dynamo_lambda_function_name}"
  write_to_dynamo_logs_group_create_arn = "arn:aws:logs:${var.current_region}:${var.current_account_id}:*"
  write_to_dynamo_log_stream_arn_prefix = "arn:aws:logs:${var.current_region}:${var.current_account_id}:log-group:${local.write_to_dynamo_log_group_name}:*"

  compare_faces_log_group_name        = "/aws/lambda/${var.compare_faces_lambda_function_name}"
  compare_faces_logs_group_create_arn = "arn:aws:logs:${var.current_region}:${var.current_account_id}:*"
  compare_faces_log_stream_arn_prefix = "arn:aws:logs:${var.current_region}:${var.current_account_id}:log-group:${local.compare_faces_log_group_name}:*"

  compare_details_log_group_name        = "/aws/lambda/${var.compare_details_lambda_function_name}"
  compare_details_logs_group_create_arn = "arn:aws:logs:${var.current_region}:${var.current_account_id}:*"
  compare_details_log_stream_arn_prefix = "arn:aws:logs:${var.current_region}:${var.current_account_id}:log-group:${local.compare_details_log_group_name}:*"

  app_api_log_group_name        = "/aws/lambda/${var.app_api_lambda_function_name}"
  app_api_logs_group_create_arn = "arn:aws:logs:${var.current_region}:${var.current_account_id}:*"
  app_api_log_stream_arn_prefix = "arn:aws:logs:${var.current_region}:${var.current_account_id}:log-group:${local.app_api_log_group_name}:*"
}

#DOCUMENT LAMBDA ROLE -------------------------------------------------------
resource "aws_iam_role" "document_lambda_role" { #the identity (Lambda) itself, with the role attached
  name = var.document_lambda_role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = "DocumentLambdaRole"
        Principal = { #Trusted entity type (Lambda)
          Service = "lambda.amazonaws.com"
        }
      },
    ]
  })
}
#INLINE S3 & DYNAMODB & SNS & SQS QUEUE POLICY
resource "aws_iam_role_policy" "document_lambda_policy" { # what the identity is allowed to do
  role = aws_iam_role.document_lambda_role.id
  name = var.document_lambda_policy_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { # S3 Get, Put, and Delete objects from Lambda
        Sid    = "S3AccessPolicy"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ],

        Resource = "${var.document_s3_bucket_arn}/*"
      },
      { # Write and update items to the newly created DynamoDB table.
        Sid    = "DynamoDBAccessPolicy"
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:UpdateItem"
        ],
        Resource = var.dynamodb_metadata_table_arn
      },
      { # Publish to the newly created SNS Topic.
        Sid    = "SNSTopicAccessPolicy"
        Effect = "Allow"
        Action = [
          "sns:Publish",
        ],
        Resource = var.sns_topic_arn
      },
      {
        "Sid" : "AllowToWriteToSQS",
        "Effect" : "Allow",
        "Action" : [
          "sqs:SendMessage"
        ],
        "Resource" : [
          var.sqs_license_queue_arn
        ]
      }
    ]
  })
}
#MANAGED CLOUDWATCH POLICY
resource "aws_iam_policy" "lambda_cloudwatch_logs_policy" { # what the identity is allowed to do
  name = var.lambda_cloudwatch_logs_policy_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { # Create Log Group
        Sid    = "CloudWatchLogGroupCreation"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
        ]
        Resource = local.logs_group_create_arn
      },
      { # Resource is scoped to this Lambda's own log group
        Sid    = "CloudWatchLogsStreamAndPut"
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = local.log_stream_arn_prefix
      }
    ]
  })
}
resource "aws_iam_role_policy_attachment" "attach_CloudWatchPolicy_to_lambdaRole" {
  policy_arn = aws_iam_policy.lambda_cloudwatch_logs_policy.arn
  role       = aws_iam_role.document_lambda_role.name
}
#So I do NOT pay for retention of data older than 14 days
resource "aws_cloudwatch_log_group" "document_lambda_logs" {
  name              = local.log_group_name
  retention_in_days = 14
}
#MANAGED REKOGNITION POLICY
resource "aws_iam_policy" "rekognition_face_comparison_policy" {
  name = var.lambda_rekognition_face_comparison_policy_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "LambdaRekonitionFaceComparison",
        Effect   = "Allow"
        Action   = ["rekognition:CompareFaces"],
        Resource = "*"
      }
    ]
  })
}
resource "aws_iam_role_policy_attachment" "attach_rekognition_policy_to_lambda" {
  policy_arn = aws_iam_policy.rekognition_face_comparison_policy.arn
  role       = aws_iam_role.document_lambda_role.name
}
# MANAGED TEXTRACT POLICY
resource "aws_iam_policy" "textract_policy" {
  name = var.lambda_textract_analyze_id_policy_name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "TextractAnalyzeId"
        Effect   = "Allow"
        Action   = ["textract:AnalyzeID"]
        Resource = "*"
      }
    ]
  })
}
resource "aws_iam_role_policy_attachment" "attach_textract_to_lambda" {
  policy_arn = aws_iam_policy.textract_policy.arn
  role       = aws_iam_role.document_lambda_role.name
}
#------------------------------------------------------------------------------


#VALIDATION LAMBDA ROLE -------------------------------------------------------
resource "aws_iam_role" "validation_lambda_role" { #the identity (Lambda) itself, with the role attached
  name = var.validate_lambda_role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = "ValidationLambdaRole"
        Principal = { #Trusted entity type (Lambda)
          Service = "lambda.amazonaws.com"
        }
      },
    ]
  })
}
# #MANAGED CLOUDWATCH POLICY
resource "aws_iam_policy" "validation_lambda_cloudwatch_logs_policy" { # what the identity is allowed to do
  name = var.validation_lambda_cloudwatch_logs_policy_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { # Create Log Group
        Sid    = "CloudWatchLogGroupCreation"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
        ]
        Resource = local.validation_logs_group_create_arn
      },
      { # Resource is scoped to this Lambda's own log group
        Sid    = "CloudWatchLogsStreamAndPut"
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = local.validation_log_stream_arn_prefix
      }
    ]
  })
}
resource "aws_iam_role_policy_attachment" "attach_CloudWatchPolicy_to_validationLambdaRole" {
  policy_arn = aws_iam_policy.validation_lambda_cloudwatch_logs_policy.arn
  role       = aws_iam_role.validation_lambda_role.name
}
resource "aws_cloudwatch_log_group" "validation_lambda_logs" {
  name              = local.validation_log_group_name
  retention_in_days = 14
}
#------------------------------------------------------------------------------


#SUBMIT LICENSE LAMBDA ROLE -------------------------------------------------------
resource "aws_iam_role" "submit_license_lambda_role" { #the identity (Lambda) itself, with the role attached
  name = var.submit_license_lambda_role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = "SubmitLicenseLambdaRole"
        Principal = { #Trusted entity type (Lambda)
          Service = "lambda.amazonaws.com"
        }
      },
    ]
  })
}
# MANAGED CLOUDWATCH POLICY
resource "aws_iam_policy" "submit_license_lambda_cloudwatch_logs_policy" { # what the identity is allowed to do
  name = var.submit_license_lambda_cloudwatch_logs_policy_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { # Create Log Group
        Sid    = "CloudWatchLogGroupCreation"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
        ]
        Resource = local.submit_license_logs_group_create_arn
      },
      { # Resource is scoped to this Lambda's own log group
        Sid    = "CloudWatchLogsStreamAndPut"
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = local.submit_license_log_stream_arn_prefix
      }
    ]
  })
}
resource "aws_iam_role_policy_attachment" "attach_CloudWatchPolicy_to_submitLicenseLambdaRole" {
  policy_arn = aws_iam_policy.submit_license_lambda_cloudwatch_logs_policy.arn
  role       = aws_iam_role.submit_license_lambda_role.name
}
resource "aws_cloudwatch_log_group" "submit_license_lambda_logs" {
  name              = local.submit_license_log_group_name
  retention_in_days = 14
}
# MANAGED SQS POLICY
resource "aws_iam_policy" "sqs_submit_license_policy" {
  name = var.sqs_submit_license_policy_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowSqsInvokeSubmitLambdaFunction"
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes"
        ]
        Resource = var.sqs_license_queue_arn
      }
    ]
  })
}
resource "aws_iam_role_policy_attachment" "attach_AmazonSQSFullAccess" {
  role       = aws_iam_role.submit_license_lambda_role.name
  policy_arn = aws_iam_policy.sqs_submit_license_policy.arn
}
# MANAGED EXECUTE-API POLICY
# The POST /license route is authorization_type = "AWS_IAM", so the SigV4 signature in
# submit_license.py is only accepted if the signing role also holds execute-api:Invoke.
# Scoped to this one method+path: the wildcard is the stage name ($default).
resource "aws_iam_policy" "execute_api_submit_license_policy" {
  name = var.execute_api_submit_license_policy_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "AllowSubmitLambdaFunctionInvokeValidationApi"
        Effect   = "Allow"
        Action   = ["execute-api:Invoke"]
        Resource = "${var.validate_license_api_execution_arn}/*/POST/license"
      }
    ]
  })
}
resource "aws_iam_role_policy_attachment" "attach_execute_api_policy_to_submit_license_role" {
  role       = aws_iam_role.submit_license_lambda_role.name
  policy_arn = aws_iam_policy.execute_api_submit_license_policy.arn
}
#INLINE S3 & DYNAMODB POLICY
resource "aws_iam_role_policy" "submit_license_lambda_policy" { # what the identity is allowed to do
  role = aws_iam_role.submit_license_lambda_role.id
  name = var.submit_license_lambda_policy_name


  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { # Write and update items to the newly created DynamoDB table.
        Sid    = "DynamoDBAccessPolicy"
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:UpdateItem"
        ],
        Resource = var.dynamodb_metadata_table_arn
      },
      { # Publish to the newly created SNS Topic.
        Sid    = "SNSTopicAccessPolicy"
        Effect = "Allow"
        Action = [
          "sns:Publish",
        ],
        Resource = var.sns_topic_arn
      },
    ]
  })
}
#------------------------------------------------------------------------------


#UNZIP LAMBDA ROLE ------------------------------------------------------------
resource "aws_iam_role" "unzip_license_lambda_role" {
  name = var.unzip_lambda_function_role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = "UnzipLicenseLambdaRole"
        Principal = { #Trusted entity type (Lambda)
          Service = "lambda.amazonaws.com"
        }
      },
    ]
  })
}
#INLINE S3 POLICY
resource "aws_iam_role_policy" "unzip_lambda_s3_policy" { # what the identity is allowed to do
  role = aws_iam_role.unzip_license_lambda_role.id
  name = "UnzipLambdaS3Policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { # S3 Get and Put objects from Lambda
        Sid    = "S3AccessPolicy"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject"
        ],
        Resource = "${var.document_s3_bucket_arn}/*"
      },
      { # The bucket is SSE-KMS, so s3:GetObject alone returns AccessDenied. Decrypt unwraps
        # the zip on download; GenerateDataKey is needed to write the extracted files back
        # to unzipped/. This is the only pipeline role that writes, so the only one with it.
        Sid    = "KMSAccessPolicy"
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ],
        Resource = var.document_kms_key_arn
      }
    ]
  })
}
# MANAGED CLOUDWATCH POLICY
resource "aws_iam_policy" "unzip_license_lambda_cloudwatch_logs_policy" { # what the identity is allowed to do
  name = var.unzip_license_lambda_cloudwatch_logs_policy_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { # Create Log Group
        Sid    = "CloudWatchLogGroupCreation"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
        ]
        Resource = local.unzip_license_logs_group_create_arn
      },
      { # Resource is scoped to this Lambda's own log group
        Sid    = "CloudWatchLogsStreamAndPut"
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = local.unzip_license_log_stream_arn_prefix
      }
    ]
  })
}
resource "aws_iam_role_policy_attachment" "attach_CloudWatchPolicy_to_unzipLicenseLambdaRole" {
  policy_arn = aws_iam_policy.unzip_license_lambda_cloudwatch_logs_policy.arn
  role       = aws_iam_role.unzip_license_lambda_role.name
}
resource "aws_cloudwatch_log_group" "unzip_license_lambda_logs" {
  name              = local.unzip_license_log_group_name
  retention_in_days = 14
}
#------------------------------------------------------------------------------

#WRITE TO DYNAMO LAMBDA ROLE ------------------------------------------------------------
resource "aws_iam_role" "write_to_dynamo_lambda_role" {
  name = var.write_to_dynamo_lambda_function_role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = "WriteToDynamoLambdaRole"
        Principal = { #Trusted entity type (Lambda)
          Service = "lambda.amazonaws.com"
        }
      },
    ]
  })
}
#INLINE S3 POLICY
resource "aws_iam_role_policy" "write_to_dynamo_lambda_s3_policy" { # what the identity is allowed to do
  role = aws_iam_role.write_to_dynamo_lambda_role.id
  name = "WriteToDynamoLambdaS3Policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { # S3 Get object from Lambda (downloads the details CSV, never uploads)
        Sid    = "S3AccessPolicy"
        Effect = "Allow"
        Action = [
          "s3:GetObject"
        ],
        Resource = "${var.document_s3_bucket_arn}/*"
      },
      { # Decrypt only - this handler downloads the details CSV and never writes to S3.
        Sid    = "KMSAccessPolicy"
        Effect = "Allow"
        Action = [
          "kms:Decrypt"
        ],
        Resource = var.document_kms_key_arn
      },
      { # Write and update items to the newly created DynamoDB table.
        Sid    = "DynamoDBAccessPolicy"
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:UpdateItem"
        ],
        Resource = var.dynamodb_metadata_table_arn
      }
    ]
  })
}
# MANAGED CLOUDWATCH POLICY
resource "aws_iam_policy" "write_to_dynamo_lambda_cloudwatch_logs_policy" { # what the identity is allowed to do
  name = var.write_to_dynamo_lambda_cloudwatch_logs_policy_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { # Create Log Group
        Sid    = "CloudWatchLogGroupCreation"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
        ]
        Resource = local.write_to_dynamo_logs_group_create_arn
      },
      { # Resource is scoped to this Lambda's own log group
        Sid    = "CloudWatchLogsStreamAndPut"
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = local.write_to_dynamo_log_stream_arn_prefix
      }
    ]
  })
}
resource "aws_iam_role_policy_attachment" "attach_CloudWatchPolicy_to_writeToDynamoLambdaRole" {
  policy_arn = aws_iam_policy.write_to_dynamo_lambda_cloudwatch_logs_policy.arn
  role       = aws_iam_role.write_to_dynamo_lambda_role.name
}
resource "aws_cloudwatch_log_group" "write_to_dynamo_lambda_logs" {
  name              = local.write_to_dynamo_log_group_name
  retention_in_days = 14
}
#INLINE X-RAY TRACING POLICY
resource "aws_iam_role_policy" "write_to_dynamo_xray_policy" { # what the identity is allowed to do
  role = aws_iam_role.write_to_dynamo_lambda_role.id
  name = "WriteToDynamoXRayTracingPolicy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { # S3 Get object from Lambda (downloads the details CSV, never uploads)
        Sid    = "XRayTracingAccessPolicy"
        Effect = "Allow"
        Action = [
          "xray:PutTraceSegments",
          "xray:PutTelemetryRecords",
          "xray:GetSamplingRules",
          "xray:GetSamplingTargets"
        ],
        Resource = ["*"]
      },
    ]
  })
}
#------------------------------------------------------------------------------


#COMPARE FACES LAMBDA ROLE ------------------------------------------------------------
resource "aws_iam_role" "compare_faces_lambda_role" {
  name = var.compare_faces_lambda_function_role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = "CompareFacesLambdaRole"
        Principal = { #Trusted entity type (Lambda)
          Service = "lambda.amazonaws.com"
        }
      },
    ]
  })
}
# MANAGED CLOUDWATCH POLICY
resource "aws_iam_policy" "compare_faces_lambda_cloudwatch_logs_policy" { # what the identity is allowed to do
  name = var.compare_faces_lambda_cloudwatch_logs_policy_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { # Create Log Group
        Sid    = "CloudWatchLogGroupCreation"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
        ]
        Resource = local.compare_faces_logs_group_create_arn
      },
      { # Resource is scoped to this Lambda's own log group
        Sid    = "CloudWatchLogsStreamAndPut"
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = local.compare_faces_log_stream_arn_prefix
      }
    ]
  })
}
resource "aws_iam_role_policy_attachment" "attach_CloudWatchPolicy_to_compareFacesLambdaRole" {
  policy_arn = aws_iam_policy.compare_faces_lambda_cloudwatch_logs_policy.arn
  role       = aws_iam_role.compare_faces_lambda_role.name
}
resource "aws_cloudwatch_log_group" "compare_faces_lambda_logs" {
  name              = local.compare_faces_log_group_name
  retention_in_days = 14
}
#INLINE S3 & DYNAMODB & SNS
resource "aws_iam_role_policy" "compare_faces_lambda_policy" { # what the identity is allowed to do
  role = aws_iam_role.compare_faces_lambda_role.id
  name = var.compare_faces_lambda_policy_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { # S3 Get, Put, and Delete objects from Lambda
        Sid    = "S3AccessPolicy"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ],

        Resource = "${var.document_s3_bucket_arn}/*"
      },
      { # Rekognition reads the license/selfie objects using THIS role's credentials, not a
        # service principal of its own, so the Decrypt grant has to live here. Decrypt only:
        # the handler never uploads, even though s3:PutObject above is granted and unused.
        Sid    = "KMSAccessPolicy"
        Effect = "Allow"
        Action = [
          "kms:Decrypt"
        ],
        Resource = var.document_kms_key_arn
      },
      { # Write and update items to the newly created DynamoDB table.
        Sid    = "DynamoDBAccessPolicy"
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:UpdateItem"
        ],
        Resource = var.dynamodb_metadata_table_arn
      },
      { # Publish to the newly created SNS Topic.
        Sid    = "SNSTopicAccessPolicy"
        Effect = "Allow"
        Action = [
          "sns:Publish",
        ],
        Resource = var.sns_topic_arn
      }
    ]
  })
}
#MANAGED REKOGNITION POLICY
resource "aws_iam_role_policy_attachment" "attach_rekognition_policy_to_compare_face_lambda" {
  policy_arn = aws_iam_policy.rekognition_face_comparison_policy.arn
  role       = aws_iam_role.compare_faces_lambda_role.name
}
#------------------------------------------------------------------------------

#COMPARE DETAILS lambda function ------------------------------------------------------------
resource "aws_iam_role" "compare_details_lambda_role" {
  name = var.compare_details_lambda_function_role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = "CompareDetailsLambdaRole"
        Principal = { #Trusted entity type (Lambda)
          Service = "lambda.amazonaws.com"
        }
      },
    ]
  })
}
# MANAGED CLOUDWATCH POLICY
resource "aws_iam_policy" "compare_details_lambda_cloudwatch_logs_policy" { # what the identity is allowed to do
  name = var.compare_details_lambda_cloudwatch_logs_policy_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { # Create Log Group
        Sid    = "CloudWatchLogGroupCreation"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
        ]
        Resource = local.compare_details_logs_group_create_arn
      },

      { # Resource is scoped to this Lambda's own log group
        Sid    = "CloudWatchLogsStreamAndPut"
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = local.compare_details_log_stream_arn_prefix
      }
    ]
  })
}
resource "aws_iam_role_policy_attachment" "attach_CloudWatchPolicy_to_compareDetailsLambdaRole" {
  policy_arn = aws_iam_policy.compare_details_lambda_cloudwatch_logs_policy.arn
  role       = aws_iam_role.compare_details_lambda_role.name
}
resource "aws_cloudwatch_log_group" "compare_details_lambda_logs" {
  name              = local.compare_details_log_group_name
  retention_in_days = 14
}
#INLINE S3 & DYNAMODB & SNS
resource "aws_iam_role_policy" "compare_details_lambda_policy" { # what the identity is allowed to do
  role = aws_iam_role.compare_details_lambda_role.id
  name = var.compare_details_lambda_policy_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { # Read the license image and details CSV from S3.
        Sid    = "S3AccessPolicy"
        Effect = "Allow"
        Action = [
          "s3:GetObject"
        ],

        Resource = "${var.document_s3_bucket_arn}/*"
      },
      { # Same as compare-faces: Textract reads the license object with this role's
        # credentials, so Decrypt belongs here. Read-only handler, so no GenerateDataKey.
        Sid    = "KMSAccessPolicy"
        Effect = "Allow"
        Action = [
          "kms:Decrypt"
        ],
        Resource = var.document_kms_key_arn
      },
      { # Update the LICENSE_DETAILS_MATCH attribute on the DynamoDB item.
        Sid    = "DynamoDBAccessPolicy"
        Effect = "Allow"
        Action = [
          "dynamodb:UpdateItem"
        ],
        Resource = var.dynamodb_metadata_table_arn
      },
      { # Publish to the newly created SNS Topic.
        Sid    = "SNSTopicAccessPolicy"
        Effect = "Allow"
        Action = [
          "sns:Publish",
        ],
        Resource = var.sns_topic_arn
      }
    ]
  })
}
# MANAGED TEXTRACT POLICY
resource "aws_iam_role_policy_attachment" "attach_textract_to_compare_details_lambda" {
  policy_arn = aws_iam_policy.textract_policy.arn
  role       = aws_iam_role.compare_details_lambda_role.name
}
#------------------------------------------------------------------------------

#APP API LAMBDA ROLE ----------------------------------------------------------
resource "aws_iam_role" "app_api_lambda_role" { #the identity (Lambda) itself, with the role attached
  name = var.app_api_lambda_function_role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = "AppApiLambdaRole"
        Principal = { #Trusted entity type (Lambda)
          Service = "lambda.amazonaws.com"
        }
      },
    ]
  })
}
#INLINE S3 & KMS & DYNAMODB POLICY
resource "aws_iam_role_policy" "app_api_lambda_policy" { # what the identity is allowed to do
  role = aws_iam_role.app_api_lambda_role.id
  name = var.app_api_lambda_policy_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { # A presigned URL is signed with THIS role's credentials, so the browser's upload is
        # authorized against this statement - not against the browser. Scoped to zipped/
        # because that is the only prefix the handler ever builds a key for.
        Sid    = "S3AccessPolicy"
        Effect = "Allow"
        Action = [
          "s3:PutObject"
        ],
        Resource = "${var.document_s3_bucket_arn}/zipped/*"
      },
      { # Required alongside the S3 statement - the bucket is SSE-KMS, so without this the
        # upload fails as AccessDenied on the S3 call. GenerateDataKey only: this function
        # never READS an object, and a presigned single PUT is not a multipart upload.
        # Add kms:Decrypt the day presigned uploads become multipart.
        Sid    = "KMSAccessPolicy"
        Effect = "Allow"
        Action = [
          "kms:GenerateDataKey"
        ],
        Resource = var.document_kms_key_arn
      },
      { # Status polling only - the pipeline owns every write to this table.
        Sid    = "DynamoDBAccessPolicy"
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem"
        ],
        Resource = var.dynamodb_metadata_table_arn
      }
    ]
  })
}
#MANAGED CLOUDWATCH POLICY
resource "aws_iam_policy" "app_api_lambda_cloudwatch_logs_policy" {
  name = var.app_api_lambda_cloudwatch_logs_policy_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { # Create Log Group
        Sid    = "CloudWatchLogGroupCreation"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
        ]
        Resource = local.app_api_logs_group_create_arn
      },

      { # Resource is scoped to this Lambda's own log group
        Sid    = "CloudWatchLogsStreamAndPut"
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = local.app_api_log_stream_arn_prefix
      }
    ]
  })
}
resource "aws_iam_role_policy_attachment" "attach_CloudWatchPolicy_to_appApiLambdaRole" {
  policy_arn = aws_iam_policy.app_api_lambda_cloudwatch_logs_policy.arn
  role       = aws_iam_role.app_api_lambda_role.name
}
resource "aws_cloudwatch_log_group" "app_api_lambda_logs" {
  name              = local.app_api_log_group_name
  retention_in_days = 14
}
#------------------------------------------------------------------------------
