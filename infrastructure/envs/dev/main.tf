# Copyright (c) 2026 Giancarlo Martinez
# SPDX-License-Identifier: Apache-2.0

terraform {
  required_version = ">= 1.10.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.4"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }
}

data "aws_caller_identity" "currentUser" {}
data "aws_region" "currentUser" {}
locals {
  env_suffix       = "-${var.project_environment}"
  site_bucket_name = "${var.site_bucket_name}${local.env_suffix}"
  # site_origin      = "http://${local.site_bucket_name}.s3-website-${data.aws_region.currentUser.region}.amazonaws.com"
  site_origin = module.cloudfront_origin.cloudfront_url
}

provider "aws" {
  region = var.project_region
  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.project_environment
      Owner       = var.project_owner
      ManagedBy   = "Terraform"
    }
  }
}

module "document_s3_bucket" {
  source                  = "../../modules/s3"
  document_s3_bucket_name = "${var.document_s3_bucket_name}${local.env_suffix}"
  document_retention_days = var.document_retention_days

  #localhost stays so "bun dev" can still hit the real backend. The presigned URL is the lock here
  document_bucket_cors_allow_origins = ["http://localhost:3000", local.site_origin]
  cors_max_age_seconds               = var.cors_max_age_seconds
}

module "customer_metadata_dynamo_db_table" {
  source                                      = "../../modules/dynamodb"
  customer_metadata_dynamo_db_table_name      = "${var.customer_metadata_dynamo_db_table_name}${local.env_suffix}"
  customer_metadata_table_class               = var.customer_metadata_table_class
  customer_metadata_table_RCU                 = var.customer_metadata_table_RCU
  customer_metadata_table_WCU                 = var.customer_metadata_table_WCU
  customer_metadata_table_autoscaling_enabled = var.customer_metadata_table_autoscaling_enabled
  customer_metadata_table_pitr_enabled        = var.customer_metadata_table_pitr_enabled
  customer_metadata_table_deletion_protection = var.customer_metadata_table_deletion_protection
  customer_metadata_table_hash_partition_key  = var.customer_metadata_table_hash_partition_key
  customer_metadata_table_max_RWcapacity      = var.customer_metadata_table_max_RWcapacity
  customer_metadata_table_min_RWcapacity      = var.customer_metadata_table_min_RWcapacity
  customer_metadata_table_target_scaling_val  = var.customer_metadata_table_target_scaling_val
}

module "app_notification_sns" {
  source                          = "../../modules/sns"
  app_notification_email_endpoint = var.app_notification_email_endpoint
  app_notification_kms_key        = var.app_notification_kms_key
  app_notification_sns_name       = "${var.app_notification_sns_name}${local.env_suffix}"
}

module "document_lambda" {
  # Module Variable = What is being passed to module var
  source = "../../modules/lambda"
  #Project
  current_region     = data.aws_region.currentUser.region
  current_account_id = data.aws_caller_identity.currentUser.account_id
  project_name       = var.project_name

  #Submit Lambda
  document_lambda_policy_name        = "${var.document_lambda_policy_name}${local.env_suffix}"
  document_lambda_role_name          = "${var.document_lambda_role_name}${local.env_suffix}"
  lambda_cloudwatch_logs_policy_name = "${var.lambda_cloudwatch_logs_policy_name}${local.env_suffix}"
  document_lambda_function_name      = "${var.document_lambda_function_name}${local.env_suffix}"
  lambda_functions_timeout           = var.lambda_functions_timeout
  sqs_license_queue_name             = module.sqs.sqs_license_queue_name
  sqs_url                            = module.sqs.sqs_url
  #Validate Lambda
  validate_lambda_function_name                 = "${var.validate_lambda_function_name}${local.env_suffix}"
  validate_lambda_role_name                     = "${var.validate_lambda_role_name}${local.env_suffix}"
  validation_lambda_cloudwatch_logs_policy_name = "${var.validation_lambda_cloudwatch_logs_policy_name}${local.env_suffix}"
  #Submit License Lambda
  submit_license_lambda_function_name               = "${var.submit_license_lambda_function_name}${local.env_suffix}"
  submit_license_lambda_role_name                   = "${var.submit_license_lambda_role_name}${local.env_suffix}"
  submit_license_lambda_cloudwatch_logs_policy_name = "${var.submit_license_lambda_cloudwatch_logs_policy_name}${local.env_suffix}"
  submit_license_lambda_policy_name                 = "${var.submit_license_lambda_policy_name}${local.env_suffix}"

  # ------- STEP FUNCTIONS LAMBDAS -------
  #Unzip License lambda
  unzip_lambda_function_name                       = "${var.unzip_lambda_function_name}${local.env_suffix}"
  unzip_lambda_function_role_name                  = "${var.unzip_lambda_function_role_name}${local.env_suffix}"
  unzip_license_lambda_cloudwatch_logs_policy_name = "${var.unzip_license_lambda_cloudwatch_logs_policy_name}${local.env_suffix}"
  #Write to Dynamo Lambda
  write_to_dynamo_lambda_function_name               = "${var.write_to_dynamo_lambda_function_name}${local.env_suffix}"
  write_to_dynamo_lambda_function_role_name          = "${var.write_to_dynamo_lambda_function_role_name}${local.env_suffix}"
  write_to_dynamo_lambda_cloudwatch_logs_policy_name = "${var.write_to_dynamo_lambda_cloudwatch_logs_policy_name}${local.env_suffix}"
  #Compare Faces Lambda
  compare_faces_lambda_function_name               = "${var.compare_faces_lambda_function_name}${local.env_suffix}"
  compare_faces_lambda_function_role_name          = "${var.compare_faces_lambda_function_role_name}${local.env_suffix}"
  compare_faces_lambda_cloudwatch_logs_policy_name = "${var.compare_faces_lambda_cloudwatch_logs_policy_name}${local.env_suffix}"
  compare_faces_lambda_policy_name                 = "${var.compare_faces_lambda_policy_name}${local.env_suffix}"
  #Compare Details Lambda
  compare_details_lambda_function_name               = "${var.compare_details_lambda_function_name}${local.env_suffix}"
  compare_details_lambda_function_role_name          = "${var.compare_details_lambda_function_role_name}${local.env_suffix}"
  compare_details_lambda_cloudwatch_logs_policy_name = "${var.compare_details_lambda_cloudwatch_logs_policy_name}${local.env_suffix}"
  compare_details_lambda_policy_name                 = "${var.compare_details_lambda_policy_name}${local.env_suffix}"

  #App API Lambda (browser-facing, not part of the document pipeline)
  app_api_lambda_function_name               = "${var.app_api_lambda_function_name}${local.env_suffix}"
  app_api_lambda_function_role_name          = "${var.app_api_lambda_function_role_name}${local.env_suffix}"
  app_api_lambda_cloudwatch_logs_policy_name = "${var.app_api_lambda_cloudwatch_logs_policy_name}${local.env_suffix}"
  app_api_lambda_policy_name                 = "${var.app_api_lambda_policy_name}${local.env_suffix}"

  #External
  document_s3_bucket_arn                         = module.document_s3_bucket.document_bucket_arn
  document_s3_bucket_name                        = module.document_s3_bucket.document_bucket_name
  document_kms_key_arn                           = module.document_s3_bucket.document_kms_key_arn
  dynamodb_document_table_name                   = module.customer_metadata_dynamo_db_table.customer_metadata_table_name
  dynamodb_metadata_table_arn                    = module.customer_metadata_dynamo_db_table.customer_metadata_table_arn
  lambda_rekognition_face_comparison_policy_name = "${var.lambda_rekognition_face_comparison_policy_name}${local.env_suffix}"
  lambda_textract_analyze_id_policy_name         = "${var.lambda_textract_analyze_id_policy_name}${local.env_suffix}"
  sns_topic_arn                                  = module.app_notification_sns.sns_topic_arn
  sns_topic_name                                 = module.app_notification_sns.sns_topic_name
  sqs_license_queue_arn                          = module.sqs.sqs_license_queue_arn
  sqs_submit_license_policy_name                 = "${var.sqs_submit_license_policy_name}${local.env_suffix}"
  validate_license_api_name                      = module.api_gateway.validate_license_api_name
  validate_license_api_url                       = module.api_gateway.license_validation_invoke_url
  validate_license_api_execution_arn             = module.api_gateway.validate_license_api_execution_arn
  # Hardcoded rather than routed through tfvars: the base name is identical in every env
  # (the suffix is what keeps the account-global managed policy name unique).
  execute_api_submit_license_policy_name = "ExecuteApiInvokeValidationApiPolicy${local.env_suffix}"
}

module "api_gateway" {
  source               = "../../modules/apiGateway"
  validate_api_gw_name = "${var.validate_api_gw_name}${local.env_suffix}"

  #External
  validate_lambda_function_name = "${var.validate_lambda_function_name}${local.env_suffix}"
  validate_lambda_invoke_arn    = module.document_lambda.validation_lambda_invoke_arn
  app_api_invoke_arn            = module.document_lambda.app_api_lambda_invoke_arn
  app_api_lambda_function_name  = module.document_lambda.app_api_lambda_function_name

  cognito_user_pool_client_id = module.congito.user_pool_client_id
  cognito_issuer              = module.congito.issuer
  #localhost stays for "bun dev". The JWT authorizer is what guards these routes,
  # CORS only decides which browser pages may call them
  api_cors_allow_origins = ["http://localhost:3000", local.site_origin]
  cors_max_age_seconds   = var.cors_max_age_seconds
}

module "sqs" {
  source         = "../../modules/sqs"
  sqs_queue_name = "${var.sqs_queue_name}${local.env_suffix}"
  sqs_dlq_name   = "${var.sqs_dlq_name}${local.env_suffix}"
}

module "step_function" {
  source             = "../../modules/stepFunction"
  current_account_id = data.aws_caller_identity.currentUser.account_id
  current_region     = data.aws_region.currentUser.region


  document_state_machine_name          = "${var.document_state_machine_name}${local.env_suffix}"
  document_state_machine_iam_role_name = "${var.document_state_machine_iam_role_name}${local.env_suffix}"

  unzip_lambda_function_arn            = module.document_lambda.unzip_lambda_function_arn
  unzip_lambda_function_name           = module.document_lambda.unzip_lambda_function_name
  write_to_dynamo_lambda_arn           = module.document_lambda.write_to_dynamo_lambda_arn
  write_to_dynamo_lambda_name          = module.document_lambda.write_to_dynamo_lambda_name
  compare_faces_lambda_function_arn    = module.document_lambda.compare_faces_lambda_function_arn
  compare_faces_lambda_function_name   = module.document_lambda.compare_faces_lambda_function_name
  compare_details_lambda_function_arn  = module.document_lambda.compare_details_lambda_function_arn
  compare_details_lambda_function_name = module.document_lambda.compare_details_lambda_function_name

  validate_sqs_queue_url = module.sqs.sqs_url
  validate_sqs_queue_arn = module.sqs.sqs_license_queue_arn

  document_s3_bucket_arn  = module.document_s3_bucket.document_bucket_arn
  document_s3_bucket_name = module.document_s3_bucket.document_bucket_name
  document_s3_bucket_id   = module.document_s3_bucket.document_bucket_id

}

# FRONT END INFRASTRUCTURE

module "congito" {
  source                        = "../../modules/cognito"
  cognito_user_pool_name        = "${var.cognito_user_pool_name}${local.env_suffix}"
  cognito_user_pool_client_name = "${var.cognito_user_pool_client_name}${local.env_suffix}"
  seed_users                    = var.seed_users
}

module "site_bucket" {
  source = "../../modules/s3Site"

  site_bucket_name = local.site_bucket_name #already has name + env suffix in locals
}

module "cloudfront_origin" {
  source                           = "../../modules/cloudfront"
  site_bucket_name                 = module.site_bucket.site_bucket_name
  site_bucket_arn                  = module.site_bucket.site_bucket_arn
  site_bucket_regional_domain_name = module.site_bucket.site_bucket_regional_domain_name
}


#FRONTEND PROVISIONING /.env.local -> Creating env variables preparing for build
resource "local_file" "frontend_env" {
  filename = "${path.root}/../../../frontend/.env.local"

  content = <<-ENV
    NEXT_PUBLIC_USER_POOL_ID=${module.congito.user_pool_id}
    NEXT_PUBLIC_USER_POOL_CLIENT_ID=${module.congito.user_pool_client_id}
    NEXT_PUBLIC_API_BASE=${module.api_gateway.api_invoke_url}
  ENV
}

resource "terraform_data" "site_deploy" {
  #re runs when there is a change in the bucket or when there are any changes
  # in the front end. You need the hash so editing anything it knows it needs to add whats new
  triggers_replace = [
    local.site_bucket_name,
    sha1(join("", [
      for f in fileset("${path.root}/../../../frontend", "{app,components,lib,public}/**") :
      filesha1("${path.root}/../../../frontend/${f}")
    ])),
    filesha1("${path.root}/../../../frontend/next.config.ts"),
  ]

  provisioner "local-exec" {
    working_dir = "${path.root}/../../../frontend"

    # Builds the site and copies out/ to the bucket. sync sets the right Content-Type
    # per file (aws_s3_object would tag them all binary/octet-stream and the CSS
    # stops loading), and --delete clears out files from older builds.
    command = "bun run build && aws s3 sync out/ s3://${local.site_bucket_name}/ --delete && aws cloudfront create-invalidation --distribution-id ${module.cloudfront_origin.cloudfront_distribution_id} --paths '/*'"
    #It does a full cache invalidation, if not CloudFront will keep saving the previous bundle till TTL is over.
    # NOTE: '/*' counts as 1 path against 1,000 free invalidation paths/mo.

  }

  #the build reads .env.local so it has to exist first, and the sync needs a bucket to target
  depends_on = [local_file.frontend_env, module.site_bucket]
}
