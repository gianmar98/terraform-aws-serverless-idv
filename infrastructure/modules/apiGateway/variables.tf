variable "validate_api_gw_name" {
  description = "This is the name of the API GW that will trigger the validation Lambda"
  type        = string
}

variable "validate_lambda_invoke_arn" {
  description = "Invoke ARN of the validation Lambda"
  type        = string
}

variable "validate_lambda_function_name" {
  description = "Function name of the validation Lambda"
  type        = string
}

# APP API LAMBDA --------
variable "app_api_invoke_arn" {
  description = "Invoke ARN of the app API Lambda."
  type        = string
}
variable "app_api_lambda_function_name" {
  description = "Function name of the app API Lambda (for the invoke permission)."
  type        = string
}


#EXTERNAL -----
variable "cognito_user_pool_client_id" {
  description = "Cognito app client ID (JWT audience)."
  type        = string
}

variable "cognito_issuer" {
  description = "Cognito JWT issuer URL."
  type        = string
}

variable "api_cors_allow_origins" {
  type        = list(string)
  description = "Allowed CORS origins (CloudFront domain + localhost for dev)."
}

variable "cors_max_age_seconds" {
  description = "How long a browser may cache the CORS preflight (OPTIONS) response for this API"
  type        = number
}