# API Gateway Module

Provisions `ValidateLicenseApi`, one HTTP API serving **two unrelated audiences**: the internal `POST /license` mock validator (IAM-authed, called server-side by the submit-license Lambda) and the browser-facing app API (`POST /api/upload-url`, `GET /api/status/{uuid}`, JWT-authed via Cognito).

## Resources

**Shared**

- `aws_apigatewayv2_api.validate_license_api` — HTTP API (`protocol_type = "HTTP"`). HTTP APIs are always Regional (no edge-optimized/private choice like REST APIs). Carries the `cors_configuration` — **CORS is API-wide, not per-route**, so it applies to `POST /license` too (harmless: that call is server-side and sends no `Origin`).
- `aws_apigatewayv2_stage.default` — the `$default` stage, `auto_deploy = true` (changes go live immediately, no manual deployment step). `default_route_settings` caps throughput at `throttling_rate_limit = 5` req/s with `throttling_burst_limit = 10` — **stage settings are not per-route**, so all three routes share this one bucket.

**Internal validator (`POST /license`)**

- `aws_apigatewayv2_integration.validation_integration` — `AWS_PROXY` integration, `payload_format_version = "2.0"`, targeting `var.validate_lambda_invoke_arn` (the validation Lambda's invoke ARN, passed in from the lambda module via the env).
- `aws_apigatewayv2_route.post_license` — routes `POST /license` to the integration, `authorization_type = "AWS_IAM"`.
- `aws_lambda_permission.apigw_invoke_validate` — grants `apigateway.amazonaws.com` permission to invoke the validation Lambda, scoped to `${execution_arn}/*/*` (`statement_id = "AllowAPIGatewayInvoke"`).

**Browser-facing app API**

- `aws_apigatewayv2_authorizer.cognito_jwt` — JWT authorizer reading `$request.header.Authorization`. `jwt_configuration.audience` is the Cognito app client ID (the token's `aud`), `issuer` is the pool URL (the token's `iss`). Both checks are needed: issuer alone accepts tokens minted for a *different app client in the same pool*; audience alone accepts a validly-signed token from *someone else's pool*.
- `aws_apigatewayv2_integration.app_api_integration` — one `AWS_PROXY` integration, `payload_format_version = "2.0"`, shared by both app routes. **2.0 is required, not cosmetic**: `app_api_lambda.py` branches on `event['routeKey']`, which only exists in the 2.0 payload shape.
- `aws_apigatewayv2_route.post_payload_url` — `POST /api/upload-url`, `authorization_type = "JWT"`. (Named `post_payload_url`, not `post_upload_url` — renaming is a destroy/create now that it's applied.)
- `aws_apigatewayv2_route.get_status` — `GET /api/status/{uuid}`, `authorization_type = "JWT"`. The `{uuid}` segment is what populates `event['pathParameters']['uuid']`; without it the path doesn't match and the request 404s before reaching the Lambda.
- `aws_lambda_permission.apigw_invoke_app_api` — invoke permission for the app API Lambda, scoped to `${execution_arn}/*/*` (`statement_id = "AllowAPIGatewayInvokeAppApi"`).

## Inputs

| Name | Type | Description |
|---|---|---|
| `validate_api_gw_name` | `string` | Name of the HTTP API |
| `validate_lambda_invoke_arn` | `string` | Invoke ARN of the validation Lambda — target of the `AWS_PROXY` integration |
| `validate_lambda_function_name` | `string` | Function name of the validation Lambda — used by the invoke permission |
| `app_api_invoke_arn` | `string` | Invoke ARN of the app API Lambda — target of the shared app integration |
| `app_api_lambda_function_name` | `string` | Function name of the app API Lambda — used by its invoke permission |
| `cognito_user_pool_client_id` | `string` | Cognito app client ID — the JWT `audience` |
| `cognito_issuer` | `string` | Cognito JWT issuer URL — the JWT `issuer` |
| `api_cors_allow_origins` | `list(string)` | Allowed CORS origins. Currently passed inline from `envs/dev/main.tf` as `["http://localhost:3000"]`, not a tfvars dial — the CloudFront domain must be added here once it exists |
 | `cors_max_age_seconds` | `number` | `cors_configuration.max_age` — how long a browser may cache the preflight. Set in `envs/dev/terraform.tfvars` (`300`) and shared with `modules/s3`'s document-bucket CORS rule, so changing it moves both |

## Outputs

| Name | Description |
|---|---|
| `validate_license_api_arn` | ARN of the HTTP API |
| `validate_license_api_name` | Name of the HTTP API — flows into the lambda module as the submit-license Lambda's `VALIDATE_LICENSE_API` env var |
| `license_validation_invoke_url` | Invoke URL for `POST /license` — flows into the lambda module as the submit-license Lambda's `VALIDATE_LICENSE_API_URL` env var (the endpoint it POSTs to) |
| `validate_license_api_execution_arn` | `execute-api` ARN — scope `execute-api:Invoke` against this, **not** the API's plain `arn` |
| `api_endpoint_host` | API host with the scheme stripped, for use as a CloudFront origin `domain_name` (which rejects a full URL). Not consumed yet — §2.5 |
| `api_invoke_url` | Base invoke URL of the `$default` stage, for the frontend's `NEXT_PUBLIC_API_BASE` in local dev. `trimsuffix`ed — the raw stage URL ends in `/` and `frontend/lib/api.ts` appends `/api/...` to it |

## Cross-module dependencies

`validate_lambda_invoke_arn` and `validate_lambda_function_name` come from the lambda module's outputs, routed through the env (`module.document_lambda.validation_lambda_invoke_arn` → `var.validate_lambda_invoke_arn`); this module's own outputs flow back into the lambda module for the submit-license Lambda's env vars. Names are env-suffixed by the caller, like every other module. The API name is the one suffix that isn't strictly required — API Gateway allows duplicate names — but it's applied anyway so there are no exceptions to explain, and unlike the IAM and SQS renames it's an in-place update, not a replacement.

## Notes

- **`POST /license` is the internal mock 3rd-party validator**, called server-side by `submit_license.py`. The frontend never calls it directly — it uses the `/api/*` routes instead.
- **Two auth schemes coexist on one API.** HTTP APIs set `authorization_type` per route, so `POST /license` stays `AWS_IAM` while the `/api/*` routes use the Cognito JWT authorizer. What is *not* per-route: CORS (API-level) and throttling (stage-level) — both are shared by all three routes.
- **Verifying the JWT routes:** an unauthenticated or malformed-token request to either `/api/*` route returns `401` (confirmed). Confirming the success path needs a real Cognito user, which does not exist yet.
- **`POST /license` requires IAM auth** (`authorization_type = "AWS_IAM"`). An unsigned request gets `403` before the integration runs, so any test call needs `--aws-sigv4` (see the command below). The only caller is `submit_license.py`, which SigV4-signs via `botocore.auth.SigV4Auth`.
- **`license_validation_invoke_url` must keep its `trimsuffix`.** The `$default` stage's `invoke_url` ends in `/`, so naive interpolation yields `…amazonaws.com//license`. HTTP API normalizes the double slash for *routing* but builds the IAM authorization ARN from the raw path (`…/POST//license`), which doesn't match the grant — a 403 that only appears once `authorization_type = "AWS_IAM"` is on.
- **Three things must agree or every call 403s**: the route's `authorization_type`, the `execute-api:Invoke` grant on the caller's role (`modules/lambda/lambda_policies.tf`, scoped to `${execution_arn}/*/POST/license`), and the signature itself. Scope the grant against `execution_arn` — the API's plain `arn` is a different ARN and will not work.
- Stage throttling (5 req/s, burst 10) is still there as defence in depth.
- Test invoke (must be signed — a plain `curl` returns `403 Missing Authentication Token`):

  ```bash
  curl -X POST "$API_ENDPOINT_URL" \
    --aws-sigv4 "aws:amz:us-east-1:execute-api" \
    --user "$AWS_ACCESS_KEY_ID:$AWS_SECRET_ACCESS_KEY" \
    -H "x-amz-security-token: $AWS_SESSION_TOKEN" \
    -H 'Content-Type: application/json' \
    -d '{"driver_license_id": "S123456579010", "validation_override": true}'
  ```

  The `x-amz-security-token` header is only needed for temporary credentials. Your own IAM identity needs `execute-api:Invoke` too — the policy in `modules/lambda/` grants it to the submit-license role only.