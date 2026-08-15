# Copyright (c) 2026 Giancarlo Martinez
# SPDX-License-Identifier: Apache-2.0

# Lambda IAM -------------------------------------------------------------------------
output "document_lambda_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.document_lambda_role.arn
}

output "document_lambda_role_name" {
  description = "Name of the Lambda execution role"
  value       = aws_iam_role.document_lambda_role.name
}

# output "document_lambda_function_arn" {
#   description = "This is the ARN of the document Lambda Function"
#   value       = aws_lambda_function.document_lambda_function.arn
# }
#
# output "document_lambda_function_name" {
#   description = "This is the name of the document Lambda Function"
#   value       = aws_lambda_function.document_lambda_function.function_name
# }

output "validation_lambda_invoke_arn" {
  description = "Invoke ARN of the validation Lambda function"
  value       = aws_lambda_function.validation_lambda_function.invoke_arn
}

# OUTPUT FOR STEP FUNCTION LAMBDAS
output "unzip_lambda_function_arn" {
  description = "This is the ARN of the 1st lambda function of the Step Function"
  value       = aws_lambda_function.unzip_lambda_function.arn
}
output "unzip_lambda_function_name" {
  description = "This is the name of the 1st lambda function of the Step Function"
  value       = aws_lambda_function.unzip_lambda_function.function_name
}

output "write_to_dynamo_lambda_arn" {
  description = "This is the ARN of the 2nd lambda function of the Step Function"
  value       = aws_lambda_function.write_to_dynamo_lambda_function.arn
}
output "write_to_dynamo_lambda_name" {
  description = "This is the name of the 2nd lambda function of the Step Function"
  value       = aws_lambda_function.write_to_dynamo_lambda_function.function_name
}

output "compare_faces_lambda_function_arn" {
  description = "This is the ARN of the 3rd lambda function of the Step Function"
  value       = aws_lambda_function.compare_faces_lambda_function.arn
}
output "compare_faces_lambda_function_name" {
  description = "This is the name of the 3rd lambda function of the Step Function"
  value       = aws_lambda_function.compare_faces_lambda_function.function_name
}

output "compare_details_lambda_function_arn" {
  description = "This is the ARN of the 2nd lambda function of the Step Function"
  value       = aws_lambda_function.compare_details_lambda_function.arn
}
output "compare_details_lambda_function_name" {
  description = "This is the name of the 2nd lambda function of the Step Function"
  value       = aws_lambda_function.compare_details_lambda_function.function_name
}

# OUTPUT FOR THE BROWSER-FACING APP API LAMBDA
output "app_api_lambda_invoke_arn" {
  description = "Invoke ARN of the app API lambda function, for the API Gateway AWS_PROXY integration"
  value       = aws_lambda_function.app_api_lambda_function.invoke_arn
}
output "app_api_lambda_function_name" {
  description = "Name of the app API lambda function, for the API Gateway lambda permission"
  value       = aws_lambda_function.app_api_lambda_function.function_name
}