output "validate_license_api_arn" {
  description = "ARN of the ValidateLicense HTTP API"
  value       = aws_apigatewayv2_api.validate_license_api.arn
}

output "validate_license_api_name" {
  description = "Name of the API GW that will receive the submission and send it to validate lambda function"
  value       = aws_apigatewayv2_api.validate_license_api.name
}

output "license_validation_invoke_url" {
  description = "Invoke URL for POST /license"
  # trimsuffix is load-bearing: the $default stage's invoke_url ends in "/", so plain
  # interpolation produced ".../amazonaws.com//license". HTTP API normalizes the double
  # slash for ROUTING but builds the IAM authorization ARN from the raw path, so the
  # request was evaluated against ".../POST//license" and denied - a 403 that only
  # appeared once authorization_type = "AWS_IAM" was turned on.
  value = "${trimsuffix(aws_apigatewayv2_stage.default.invoke_url, "/")}/license"
}

output "validate_license_api_execution_arn" {
  description = "execute-api ARN of the API (arn:aws:execute-api:region:account:api-id) — scope execute-api:Invoke against this, not the API's own ARN"
  value       = aws_apigatewayv2_api.validate_license_api.execution_arn
}

# Regional API host (no scheme) for use as a CloudFront origin domain.
output "api_endpoint_host" {
  description = "API Gateway host, e.g. abc123.execute-api.us-east-1.amazonaws.com"
  #CLOUDFRONT wants bare host name, not a URL
  value = replace(aws_apigatewayv2_api.validate_license_api.api_endpoint, "https://", "")
}
output "api_invoke_url" {
  description = "Base invoke URL of the $default stage, no trailing slash (for local dev NEXT_PUBLIC_API_BASE)."
  # trimsuffix for the same reason as license_validation_invoke_url: the $default stage's
  # invoke_url ends in "/", and the frontend appends "/api/..." to it.
  value = trimsuffix(aws_apigatewayv2_stage.default.invoke_url, "/")
}