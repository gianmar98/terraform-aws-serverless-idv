#TEST API INVOKE ENDPOINT
# curl -X POST -H 'Content-Type: application/json' -d '{"driver_license_id": "S123456579010", "validation_override": "True"}' $API_ENDPOINT_URL

# curl -X POST -H 'Content-Type: application/json' -d '{"driver_license_id": "S123456579010", "validation_override": "False"}' $API_ENDPOINT_URL

#aws logs tail /aws/lambda/ValidateLicenseLambdaFunctionU

#The API resource itself ------------
#(UPDATE) Add CORS to existing API resource (so different origin than cloudfront can call it)"
resource "aws_apigatewayv2_api" "validate_license_api" {
  name          = var.validate_api_gw_name
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins     = var.api_cors_allow_origins #Cloudfront + localhost:3000
    allow_methods     = ["GET", "POST", "OPTIONS"]
    allow_headers     = ["authorization", "content-type"]
    allow_credentials = false
    max_age           = var.cors_max_age_seconds
  }
}
#------------------------------------


# ---- Validation API (unauthorized-protected) --------------------------------
#The target, what to call when request arrives (AWS Proxy means send request to lambda and return what lambda returns)
resource "aws_apigatewayv2_integration" "validation_integration" {
  api_id                 = aws_apigatewayv2_api.validate_license_api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = var.validate_lambda_invoke_arn
  payload_format_version = "2.0"
}
#Rule that maps POST /license integration
resource "aws_apigatewayv2_route" "post_license" {
  api_id    = aws_apigatewayv2_api.validate_license_api.id
  route_key = "POST /license"
  target    = "integrations/${aws_apigatewayv2_integration.validation_integration.id}"

  # Needs execute-api:Invoke on this route; everyone else gets 403 before the Lambda runs.
  # Sole caller is the submit-license Lambda, which SigV4-signs its request (src/submit_license.py).
  authorization_type = "AWS_IAM"
}
#Deployment slot where APIs can live ($default is the catch-all stage) (auto deploy deploy changes instantly)
resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.validate_license_api.id
  name        = "$default"
  auto_deploy = true

  # Spend cap, shared by EVERY route on this API - stage settings are not per-route.
  # 5 req/s sustained, bursting to 10: far above what the pipeline needs (one call per
  # application) and low enough that a runaway caller costs nothing.
  default_route_settings {
    throttling_burst_limit = 10
    throttling_rate_limit  = 5
  }
}
#IAM Door
resource "aws_lambda_permission" "apigw_invoke_validate" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = var.validate_lambda_function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.validate_license_api.execution_arn}/*/*"
}
#--------------------------------------------------------

# ---- Browser-facing app API (auth-protected) --------------------------------
# JWT authorizer backed by the Cognito user pool.
# Validates token's issuer + audience on every request before Lambda is called.
resource "aws_apigatewayv2_authorizer" "cognito_jwt" {
  api_id           = aws_apigatewayv2_api.validate_license_api.id
  authorizer_type  = "JWT"
  identity_sources = ["$request.header.Authorization"]
  name             = "cognito-jwt"

  jwt_configuration {

    #app client (app's registered doorway to the box of users)
    audience = [var.cognito_user_pool_client_id] #WHO the TOKEN was MADE FOR
    issuer   = var.cognito_issuer                #WHO made the token (pool)
  }
}
# AWS_PROXY integration reused by both app routes
resource "aws_apigatewayv2_integration" "app_api_integration" {
  api_id           = aws_apigatewayv2_api.validate_license_api.id
  integration_type = "AWS_PROXY"

  integration_uri        = var.app_api_invoke_arn
  payload_format_version = "2.0" #2.0 is HTTP API native payload (event["requestContext"]["http"]["method"])
}
#Rule that maps POST /api/upload-url integration
resource "aws_apigatewayv2_route" "post_upload_url" {
  api_id             = aws_apigatewayv2_api.validate_license_api.id
  route_key          = "POST /api/upload-url"
  target             = "integrations/${aws_apigatewayv2_integration.app_api_integration.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito_jwt.id
}
#Rule that maps GET /api/status integration
resource "aws_apigatewayv2_route" "get_status" {
  api_id             = aws_apigatewayv2_api.validate_license_api.id
  route_key          = "GET /api/status/{uuid}"
  target             = "integrations/${aws_apigatewayv2_integration.app_api_integration.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito_jwt.id
}
#Lambda permission to be invoked by API GW
resource "aws_lambda_permission" "apigw_invoke_app_api" {
  statement_id  = "AllowAPIGatewayInvokeAppApi"
  action        = "lambda:InvokeFunction"
  function_name = var.app_api_lambda_function_name
  principal     = "apigateway.amazonaws.com"

  #because arn shape is arn:aws:execute-api:us-east-1:<account>:<api-id>/<stage>/<METHOD>/<path>
  # so any stage and any method+path
  source_arn = "${aws_apigatewayv2_api.validate_license_api.execution_arn}/*/*"
}







