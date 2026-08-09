# Lambda Module

Provisions eight Lambda functions — the document-handling Lambda, the mock validation Lambda, the SQS-triggered submit-license Lambda, the four-step pipeline (unzip → write-to-DynamoDB → compare-faces → compare-details), and the browser-facing app API Lambda — along with their execution roles + policies and CloudWatch log groups.

**Only one trigger lives in this module:** the SQS event source mapping for the submit-license Lambda. The four pipeline Lambdas are invoked by the `DocumentStateMachine` in `modules/stepFunction/`, which is also where the bucket's EventBridge notification lives. The app API Lambda is invoked by API Gateway, so its `aws_lambda_permission` belongs in `modules/apiGateway/` — that resource **does not exist yet**, so the function currently deploys with nothing able to invoke it. **`document_lambda_function.tf` is now commented out in full** — the monolithic function is no longer deployed at all (see Notes).

**The app API Lambda is the only function here that is not part of the document pipeline.** It serves the Next.js frontend: it mints presigned S3 PUT URLs so the browser can upload without AWS credentials, and reads submission status back out of DynamoDB. See `frontend_tutorial.md` §2.2.

> Resource names are env-stamped **before** they reach this module — `envs/dev/main.tf` appends `-${project_environment}` to **every** name input, with no exceptions. The module itself is env-agnostic and uses each name as-is.
>
> This module declares its own `required_providers` in `versions.tf` (`aws ~> 6.4`, `archive ~> 2.8` — it's the only module that zips deployment packages). Keep both as ranges, not exact pins, or they will conflict with the sibling modules' constraints during `terraform init`.

## Files

- `versions.tf` — `required_version` + `required_providers` (`aws`, `archive`).
- `lambda_policies.tf` — IAM roles, inline policy (S3/DynamoDB/SNS), CloudWatch Logs policies + attachments, Rekognition policy + attachment, Textract policy + attachments, the submit-license SQS poll policy + attachment, and log groups for all eight Lambda functions.
- `document_lambda_function.tf` — **entirely commented out.** Held the `archive_file`, the document Lambda function, its `lambda:InvokeFunction` permission for S3, and the (already-disabled) `aws_s3_bucket_notification`. Its two outputs in `outputs.tf` are commented out to match; the role, policies, and log group in `lambda_policies.tf` remain and are now orphaned.
- `validate_lambda_function.tf` — `archive_file` packaging and the validation Lambda function (mock 3rd-party license validation).
- `submit_license_lambda_function.tf` — `archive_file` packaging, the submit-license Lambda function, and the `aws_lambda_event_source_mapping` that wires `LicenseQueue` to it (`batch_size = 1`).
- `unzip_lambda_function.tf` — `archive_file` packaging and the unzip Lambda function. No `environment` block configured (commented out); invoked by the state machine.
- `write_to_dynamo_lambda_function.tf` — `archive_file` packaging and the write-to-DynamoDB Lambda function. Exposes `TABLE` as a runtime env var; invoked by the state machine.
- `compare_faces_lambda_function.tf` — `archive_file` packaging and the compare-faces Lambda function. Exposes `TABLE` and `TOPIC` as runtime env vars; invoked by the state machine.
- `compare_details_lambda_function.tf` — `archive_file` packaging and the compare-details Lambda function. Exposes `TABLE` and `TOPIC` as runtime env vars; invoked by the state machine.
- `app_api_lambda_function.tf` — `archive_file` packaging and the app API Lambda function. Exposes `BUCKET` and `TABLE` as runtime env vars — no `TOPIC` or `SQS_URL`, since it publishes and consumes nothing. **No trigger resource**: API Gateway invokes it, so the `aws_lambda_permission` lives in `modules/apiGateway/`.
- `src/s3_upload.py` — Python 3.13 document-processing handler. The monolithic equivalent of the four-step pipeline below, in one function; **no longer triggered** (its S3 notification is commented out), so this describes what it does when invoked manually. Full invocation flow: (1) downloads and extracts the triggering zip into `/tmp/unzipped/`, re-uploads each file to `unzipped/` in S3; (2) `parse_csv_ddb` reads `<app_uuid>_details.csv` via `csv.DictReader` + `next()` and writes the row + `APP_UUID` to DynamoDB via `put_item`; (3) `compare_faces` calls Rekognition `compare_faces` using S3 object references (not local bytes) with `SimilarityThreshold=80`, derives `LICENSE_SELFIE_MATCH = True/False` from `FaceMatches`; (4) updates the DynamoDB item with `LICENSE_SELFIE_MATCH` via `update_item`; (5) publishes a failure message to SNS if `LICENSE_SELFIE_MATCH` is `False`; (6) `textract_response` extracts the license's identity fields via `analyze_id`; (7) `compare_dictionaries` does an exact string equality check of the CSV vs Textract subsets and writes `LICENSE_DETAILS_MATCH` to DynamoDB, publishing to SNS on mismatch; (8) sends `{"driver_license_id": details_dict['DOCUMENT_NUMBER'], "validation_override": True, "uuid": app_uuid}` to `LicenseQueue` via `sqs.send_message` (JSON body), inside a `try/except ClientError` — `ClientError` is imported from `botocore.exceptions`, so a send failure is caught rather than raising `NameError`. **The handler does not raise on a mismatch** — all checks run every invocation, then the SQS message is always sent. Reads `TABLE`, `TOPIC`, and `SQS_URL` from environment variables.
- `src/validate_lambda.py` — Python 3.13 mock validation handler. Reads `driver_license_id` and `validation_override` from the API Gateway event body and returns `validation_override` directly (simulates both true and false validation outcomes).
- `src/submit_license.py` — Python 3.13 submit-license handler (`batch_size = 1`, so always `event['Records'][0]`). Parses `driver_license_id`, `validation_override`, `uuid` from the SQS record's `body`; SigV4-signs the payload with `botocore.auth.SigV4Auth` (signing name `execute-api`) using the execution role's credentials, then POSTs it to the validation endpoint at `VALIDATE_LICENSE_API_URL` via `urllib3` and waits for the response — the route is `AWS_IAM`-authorised, so an unsigned request would 403. **It raises on any non-200 before parsing**: an API Gateway error body is still valid JSON (`{"message": "Forbidden"}` on a 403), so parsing unconditionally would write that dict into `LICENSE_VALIDATION` instead of the validator's true/false. Then it writes `LICENSE_VALIDATION` to DynamoDB via `update_item` on `APP_UUID` for both `True`/`False` outcomes; on `False`, also publishes a failure notification to SNS. Reads `TABLE`, `TOPIC` (must be the topic **ARN**), `VALIDATE_LICENSE_API`, and `VALIDATE_LICENSE_API_URL` from environment variables. **The `except` block ends in a bare `raise`** (the previous `return {"statusCode": 500, ...}` is kept commented beneath it) — see the DLQ note below.
- `src/unzip_lambda.py` — Python 3.13 unzip handler, first step of the pipeline. Expects `event['detail']['bucket']['name']` and `event['detail']['object']['key']` (e.g. `zipped/<app_uuid>.zip`). Wraps its body in `try/finally` — clears and recreates `/tmp/unzipped/` at the start (so a warm container can't leak files from a prior invocation) and always `shutil.rmtree`s it again in `finally`. `unzip_object` enforces two size ceilings before doing anything expensive — `head_object` against `MAX_ZIP_BYTES` (20MB) **before** `download_file`, so an oversized upload never lands on `/tmp`, then `sum(i.file_size for i in zip_ref.infolist())` against `MAX_UNCOMPRESSED_BYTES` (50MB, vs the 512MB `/tmp`) before `extractall`. The second is the actual zip-bomb defence: a bomb declaring 50MB extracted compresses to tens of KB and sails past any compressed-size limit. Both raise `ValueError`, which propagates out and fails the state machine step. `head_object` authorizes as `s3:GetObject`, so no IAM change was needed. It then downloads the zip to `/tmp/`, extracts every member into `/tmp/unzipped/` (creating the dir if missing), deletes the local zip, and filters out `__`-prefixed junk (e.g. macOS's `__MACOSX`) from the returned file list. The handler re-uploads each extracted file to the `unzipped/` prefix in S3, derives `app_uuid` from the zip's filename (`os.path.basename(key).replace(".zip", "")`), and returns `{"app_uuid": app_uuid}`. No environment variables read.
- `src/write_to_dynamo_lambda.py` — Python 3.13 handler, second step of the pipeline (runs after the unzip Lambda, whose return value the state machine places at `$.application`). Expects `event['detail']['bucket']['name']` and `event['application']['app_uuid']`. Downloads `unzipped/<app_uuid>_details.csv` from S3 to `/tmp/`, parses it with `csv.DictReader` + `next()`, and writes the row + `APP_UUID` to DynamoDB via `put_item`. Returns `{"driver_license_id": <CSV DOCUMENT_NUMBER>, "validation_override": True, "app_uuid": app_uuid}` — shaped for a downstream state to hand off to submit-license validation. Reads `TABLE` from environment variables. **Instrumented for X-Ray:** imports `Tracer` from `aws_lambda_powertools` (layer-provided), instantiates `tracer = Tracer()` at module scope, and decorates the handler with `@tracer.capture_lambda_handler`. Instantiating the tracer patches botocore, so the S3 and DynamoDB calls emit their own subsegments; the decorator adds the `## lambda_handler` subsegment plus `ColdStart`/`Service` annotations and records the return value as trace metadata.
- `src/compare_faces_lambda.py` — Python 3.13 handler, third step of the pipeline. Expects `event['application']['app_uuid']` and `event['detail']['bucket']['name']`; derives `unzipped/<app_uuid>_selfie.png` and `unzipped/<app_uuid>_license.png` as the S3 keys to compare. `compare_faces` calls Rekognition `compare_faces` with `SimilarityThreshold=80` (wrapped in `try/except` — any Rekognition error is logged and treated as a non-match rather than aborting the invocation), sets `LICENSE_SELFIE_MATCH` in DynamoDB via `update_item` regardless of outcome, and publishes a failure notification to SNS when the match is `False`. `lambda_handler` **raises `ValueError`** on a non-match (unlike `s3_upload.py`'s monolithic flow, which never raises) — this makes a face-match failure surface as a Lambda invocation failure, e.g. for a Step Functions `Catch` block — and otherwise returns `True`. Reads `TABLE` and `TOPIC` from environment variables.
- `src/compare_details_lambda.py` — Python 3.13 handler, fourth step of the pipeline. Expects `event['detail']['bucket']['name']` and `event['application']['app_uuid']`; derives `unzipped/<app_uuid>_details.csv` and `unzipped/<app_uuid>_license.png` as the S3 keys. Downloads the details CSV to `/tmp/` and parses it with `csv.DictReader` + `next()`; `textract_response` extracts the license's identity fields via `analyze_id`, keeping only the eight required fields (`DOCUMENT_NUMBER`, `FIRST_NAME`, `LAST_NAME`, `DATE_OF_BIRTH`, `ADDRESS`, `STATE_IN_ADDRESS`, `CITY_IN_ADDRESS`, `ZIP_CODE_IN_ADDRESS`). `compare_dictionaries` narrows **both** the CSV and Textract sides to those fields (via `.get(k, '')`) and compares them, writes `LICENSE_DETAILS_MATCH` to DynamoDB via `update_item` regardless of outcome, and on a mismatch publishes a failure notification to SNS and **raises `ValueError`** (same fail-loud pattern as `compare_faces_lambda.py`; the DDB update and SNS publish both run before the raise). Otherwise the handler returns `True`. Reads `TABLE` and `TOPIC` (must be the topic **ARN**) from environment variables at import time. **Compares against the CSV in S3, not a `get_item` on the DynamoDB row** — the two carry the same values since the row was populated from that CSV upstream.

- `src/app_api_lambda.py` — Python 3.13 browser-facing API handler, routed on `event['routeKey']` (HTTP API v2 payload format). `POST /api/upload-url` mints an 8-hex `app_uuid`, builds the key `zipped/<app_uuid>.zip`, and returns a **presigned S3 PUT URL** (300s expiry) as `{"uuid", "key", "url"}` — `generate_presigned_url` signs locally and makes no API call, so signing itself needs no permission; the grants matter when the *browser* uses the URL. `GET /api/status/{uuid}` validates the path parameter is exactly 8 hex chars (**anything over 2048 bytes would raise `ValidationException` from DynamoDB and surface as a bodyless 502**), then does a `get_item` on `APP_UUID`. It answers `{"status": "pending"}` both when no row exists *and* when the row exists without all three of `LICENSE_SELFIE_MATCH` / `LICENSE_DETAILS_MATCH` / `LICENSE_VALIDATION` — WriteToDynamo creates the row long before the flags land, so keying `done` off the row's existence would stop the browser polling on a half-finished run. **This is the one handler here that returns errors instead of raising** (`except ClientError` → 500): API Gateway renders an unhandled exception as a bodyless 502 the browser can't act on, the opposite of what SQS redrive and Step Functions `Catch` need. Reads `BUCKET` and `TABLE` from environment variables. Uses the boto3 **resource** API, so DynamoDB values come back as plain Python bools rather than `{"BOOL": true}`.

## Resources

### Document Lambda

- `aws_iam_role.document_lambda_role` — assume-role trust for `lambda.amazonaws.com`. Trust-policy `Sid` is the literal `"DocumentLambdaRole"` (IAM Sids must be alphanumeric).
- `aws_iam_role_policy.document_lambda_policy` — **inline** policy granting:
  - `s3:GetObject`, `s3:PutObject`, `s3:DeleteObject` on `${document_s3_bucket_arn}/*`
  - `dynamodb:PutItem`, `dynamodb:UpdateItem` on `${dynamodb_metadata_table_arn}`
  - `sns:Publish` on `${sns_topic_arn}`
- `aws_iam_policy.lambda_cloudwatch_logs_policy` — **customer-managed** least-privilege CloudWatch: `CreateLogGroup` on `arn:aws:logs:<region>:<account>:*`; `CreateLogStream`/`PutLogEvents` scoped to `/aws/lambda/<function_name>:*`.
- `aws_iam_role_policy_attachment.attach_CloudWatchPolicy_to_lambdaRole` — attaches the CW policy to the document Lambda role.
- `aws_iam_policy.rekognition_face_comparison_policy` — **customer-managed** policy granting `rekognition:CompareFaces` on `*`. Name is env-suffixed via `var.lambda_rekognition_face_comparison_policy_name`.
- `aws_iam_role_policy_attachment.attach_rekognition_policy_to_lambda` — attaches the Rekognition policy to the document Lambda role.
- `aws_iam_policy.textract_policy` — **customer-managed** policy granting `textract:AnalyzeID` on `*`. Name is env-suffixed via `var.lambda_textract_analyze_id_policy_name`.
- `aws_iam_role_policy_attachment.attach_textract_to_lambda` — attaches the Textract policy to the document Lambda role.
- `aws_cloudwatch_log_group.document_lambda_logs` — `/aws/lambda/<function_name>`, 14-day retention. Function name carries the env suffix, so the log group does too.
- The `archive_file`, `aws_lambda_function.document_lambda_function`, `aws_s3_bucket_notification.document_bucket_notification`, and `aws_lambda_permission.allow_s3_invoke` are **all commented out** — see Notes. `src/s3_upload.py` is still on disk, so uncommenting restores the function.

> The role, its inline/managed policies, the attachments above, and `document_lambda_logs` still deploy and are attached to nothing. `local.log_group_name` in `lambda_policies.tf` also still interpolates `var.document_lambda_function_name`, so that variable must stay wired through `envs/dev/` even though no function consumes it.

### Validation Lambda

- `aws_iam_role.validation_lambda_role` — assume-role trust for `lambda.amazonaws.com`. Trust-policy `Sid` is the literal `"ValidationLambdaRole"` (Sids stay unsuffixed — IAM requires them to be alphanumeric).
- `aws_iam_policy.validation_lambda_cloudwatch_logs_policy` — **customer-managed** least-privilege CloudWatch policy, same scope pattern as the document Lambda policy.
- `aws_iam_role_policy_attachment.attach_CloudWatchPolicy_to_validationLambdaRole` — attaches the CW policy to the validation Lambda role.
- `aws_cloudwatch_log_group.validation_lambda_logs` — `/aws/lambda/<validate_lambda_function_name>`, 14-day retention.
- `data.archive_file.validate_lambda_function_archive_file` — zips `src/validate_lambda.py` to `build/validate_lambda.zip`.
- `aws_lambda_function.validation_lambda_function` — Python 3.13, handler `validate_lambda.lambda_handler`, `source_code_hash` from the archive. No logging config or environment variables configured yet.

### Submit License Lambda

- `aws_iam_role.submit_license_lambda_role` — assume-role trust for `lambda.amazonaws.com`. Trust-policy `Sid` is the literal `"SubmitLicenseLambdaRole"`.
- `aws_iam_policy.submit_license_lambda_cloudwatch_logs_policy` — **customer-managed** least-privilege CloudWatch policy, same scope pattern as the document Lambda policy.
- `aws_iam_role_policy_attachment.attach_CloudWatchPolicy_to_submitLicenseLambdaRole` — attaches the CW policy to the submit-license role.
- `aws_iam_policy.execute_api_submit_license_policy` — **customer-managed** policy granting `execute-api:Invoke` on `${var.validate_license_api_execution_arn}/*/POST/license`, attached via `aws_iam_role_policy_attachment.attach_execute_api_policy_to_submit_license_role`. Without it the SigV4 signature is rejected and every call 403s.
- `aws_iam_policy.sqs_submit_license_policy` — **customer-managed** policy granting `sqs:ReceiveMessage`/`sqs:DeleteMessage`/`sqs:GetQueueAttributes` scoped to `var.sqs_license_queue_arn` (the canonical poll permissions for an SQS-triggered Lambda; no `aws_lambda_permission` is needed because SQS is a poll source, not a push source).
- `aws_iam_role_policy_attachment.attach_AmazonSQSFullAccess` — attaches the SQS policy to the submit-license role. *(Resource label is a misnomer — it's the scoped policy above, not the AWS-managed `AmazonSQSFullAccess`.)*
- `aws_cloudwatch_log_group.submit_license_lambda_logs` — `/aws/lambda/<submit_license_lambda_function_name>`, 14-day retention.
- `data.archive_file.submit_license_lambda_function_archive_file` — zips `src/submit_license.py` to `build/submit_license.zip`.
- `aws_lambda_function.submit_license_lambda_function` — Python 3.13, handler `submit_license.lambda_handler`, wired to its log group via `logging_config`. Exposes `VALIDATE_LICENSE_API`, `VALIDATE_LICENSE_API_URL`, `TOPIC` (SNS topic ARN), and `TABLE` (DynamoDB table name) as runtime env vars.
- `aws_lambda_event_source_mapping.sqs_trigger_submit_license_lambda` — polls `var.sqs_license_queue_arn` (the `LicenseQueue`) and invokes the function with `batch_size = 1`. Enabled by default.

All submit-license names (function, role, CW policy, SQS policy) are env-suffixed by the caller — as is every other name input to this module.

### Unzip Lambda

- `aws_iam_role.unzip_license_lambda_role` — assume-role trust for `lambda.amazonaws.com`. Trust-policy `Sid` is the literal `"UnzipLicenseLambdaRole"` (Sids stay unsuffixed — IAM requires them to be alphanumeric).
- `aws_iam_role_policy.unzip_lambda_s3_policy` — **inline** policy granting `s3:GetObject`/`s3:PutObject` on `${document_s3_bucket_arn}/*`, plus `kms:Decrypt`/`kms:GenerateDataKey` on `${document_kms_key_arn}` (`KMSAccessPolicy`). The only pipeline role with `GenerateDataKey` — it's the only one that writes objects back.
- `aws_iam_policy.unzip_license_lambda_cloudwatch_logs_policy` — **customer-managed** least-privilege CloudWatch policy, same scope pattern as the document Lambda policy.
- `aws_iam_role_policy_attachment.attach_CloudWatchPolicy_to_unzipLicenseLambdaRole` — attaches the CW policy to the unzip Lambda role.
- `aws_cloudwatch_log_group.unzip_license_lambda_logs` — `/aws/lambda/<unzip_lambda_function_name>`, 14-day retention.
- `data.archive_file.unzip_lambda_function_archive_file` — zips `src/unzip_lambda.py` to `build/unzip_lambda.zip`.
- `aws_lambda_function.unzip_lambda_function` — Python 3.13, handler `unzip_lambda.lambda_handler`, wired to its log group via `logging_config`. No environment variables configured (block commented out). No event source of its own — invoked as step 1 by `DocumentStateMachine`.

### Write-to-DynamoDB Lambda

- `aws_iam_role.write_to_dynamo_lambda_role` — assume-role trust for `lambda.amazonaws.com`. Trust-policy `Sid` is the literal `"WriteToDynamoLambdaRole"` (Sids stay unsuffixed — IAM requires them to be alphanumeric).
- `aws_iam_role_policy.write_to_dynamo_lambda_s3_policy` — **inline** policy granting `s3:GetObject` on `${document_s3_bucket_arn}/*` (downloads the details CSV only, never uploads), `kms:Decrypt` on `${document_kms_key_arn}`, and `dynamodb:PutItem`/`dynamodb:UpdateItem` on `${dynamodb_metadata_table_arn}`.
- `aws_iam_role_policy.write_to_dynamo_xray_policy` — **inline** policy (`WriteToDynamoXRayTracingPolicy`) granting `xray:PutTraceSegments`/`PutTelemetryRecords`/`GetSamplingRules`/`GetSamplingTargets` on `*` (X-Ray has no resource-level permissions). Required by the tracing config below — see Notes.
- `aws_iam_policy.write_to_dynamo_lambda_cloudwatch_logs_policy` — **customer-managed** least-privilege CloudWatch policy, same scope pattern as the document Lambda policy.
- `aws_iam_role_policy_attachment.attach_CloudWatchPolicy_to_writeToDynamoLambdaRole` — attaches the CW policy to the write-to-dynamo Lambda role.
- `aws_cloudwatch_log_group.write_to_dynamo_lambda_logs` — `/aws/lambda/<write_to_dynamo_lambda_function_name>`, 14-day retention.
- `data.archive_file.write_to_dynamo_lambda_function_archive_file` — zips `src/write_to_dynamo_lambda.py` to `build/write_to_dynamo_lambda.zip`.
- `aws_lambda_function.write_to_dynamo_lambda_function` — Python 3.13, handler `write_to_dynamo_lambda.lambda_handler`, wired to its log group via `logging_config`. Exposes `TABLE` and `POWERTOOLS_SERVICE_NAME` (`= var.project_name`) as runtime env vars (`TOPIC`/`SQS_URL` inputs are commented out — unused by this handler). No event source of its own — invoked as step 2 by `DocumentStateMachine`.
  **The only traced function in this module:** `tracing_config { mode = "Active" }` plus the AWS-hosted Powertools layer (`AWSLambdaPowertoolsPythonV3-python313-x86_64:36`, account `017000801446`, region from `var.current_region`). The layer supplies `aws_lambda_powertools`, which the handler imports — it is **not** in the deployment zip.

### Compare-Faces Lambda

- `aws_iam_role.compare_faces_lambda_role` — assume-role trust for `lambda.amazonaws.com`. Trust-policy `Sid` is the literal `"CompareFacesLambdaRole"` (Sids stay unsuffixed — IAM requires them to be alphanumeric).
- `aws_iam_role_policy.compare_faces_lambda_policy` — **inline** policy granting `s3:GetObject`/`s3:PutObject`/`s3:DeleteObject` on `${document_s3_bucket_arn}/*`, `kms:Decrypt` on `${document_kms_key_arn}` (Rekognition reads the images with this role's credentials), `dynamodb:PutItem`/`dynamodb:UpdateItem` on `${dynamodb_metadata_table_arn}`, and `sns:Publish` on `${sns_topic_arn}`.
- `aws_iam_policy.compare_faces_lambda_cloudwatch_logs_policy` — **customer-managed** least-privilege CloudWatch policy, same scope pattern as the document Lambda policy.
- `aws_iam_role_policy_attachment.attach_CloudWatchPolicy_to_compareFacesLambdaRole` — attaches the CW policy to the compare-faces Lambda role.
- `aws_iam_role_policy_attachment.attach_rekognition_policy_to_compare_face_lambda` — attaches the shared `rekognition_face_comparison_policy` (same customer-managed policy the document Lambda uses) to the compare-faces Lambda role.
- `aws_cloudwatch_log_group.compare_faces_lambda_logs` — `/aws/lambda/<compare_faces_lambda_function_name>`, 14-day retention.
- `data.archive_file.compare_faces_lambda_function_archive_file` — zips `src/compare_faces_lambda.py` to `build/compare_faces_lambda.zip`.
- `aws_lambda_function.compare_faces_lambda_function` — Python 3.13, handler `compare_faces_lambda.lambda_handler`, wired to its log group via `logging_config`. Exposes `TABLE` and `TOPIC` as runtime env vars. No event source of its own — invoked as step 3(a) by `DocumentStateMachine`.

### Compare-Details Lambda

- `aws_iam_role.compare_details_lambda_role` — assume-role trust for `lambda.amazonaws.com`. Trust-policy `Sid` is the literal `"CompareDetailsLambdaRole"` (Sids stay unsuffixed — IAM requires them to be alphanumeric).
- `aws_iam_role_policy.compare_details_lambda_policy` — **inline** policy granting `s3:GetObject` on `${document_s3_bucket_arn}/*` (reads the license image + details CSV only), `kms:Decrypt` on `${document_kms_key_arn}` (Textract reads the license image with this role's credentials), `dynamodb:UpdateItem` on `${dynamodb_metadata_table_arn}` (sets `LICENSE_DETAILS_MATCH`), and `sns:Publish` on `${sns_topic_arn}`. Scoped tighter than the compare-faces inline policy — no `PutObject`/`DeleteObject`/`PutItem`, since this handler only reads and updates.
- `aws_iam_policy.compare_details_lambda_cloudwatch_logs_policy` — **customer-managed** least-privilege CloudWatch policy, same scope pattern as the document Lambda policy.
- `aws_iam_role_policy_attachment.attach_CloudWatchPolicy_to_compareDetailsLambdaRole` — attaches the CW policy to the compare-details Lambda role.
- `aws_iam_role_policy_attachment.attach_textract_to_compare_details_lambda` — attaches the shared `textract_policy` (`textract:AnalyzeID`, same customer-managed policy the document Lambda uses) to the compare-details Lambda role.
- `aws_cloudwatch_log_group.compare_details_lambda_logs` — `/aws/lambda/<compare_details_lambda_function_name>`, 14-day retention.
- `data.archive_file.compare_details_lambda_function_archive_file` — zips `src/compare_details_lambda.py` to `build/compare_details_lambda.zip`.
- `aws_lambda_function.compare_details_lambda_function` — Python 3.13, handler `compare_details_lambda.lambda_handler`, wired to its log group via `logging_config`. Exposes `TABLE` and `TOPIC` as runtime env vars. No event source of its own — invoked as step 3(b) by `DocumentStateMachine`.

**`normalize()` — why the comparison is not raw string equality.** The two sides are written by different authors: the CSV is typed by a human or a web form, the other side is Textract reading the printed licence. They agree on the facts and disagree on formatting — a licence prints `NICK` / `01/12/1957` where a form submits `Nick` / `1957-01-12`. Raw `==` rejected a *correct* applicant on 5 of 8 fields (4 case, 1 date format). `normalize()` applies `.strip().upper()` to every field and, for `DATE_OF_BIRTH`, parses `%Y-%m-%d` then `%m/%d/%Y` and re-emits ISO. An unparseable date falls through to a text compare, so garbage still fails rather than matching other garbage. A mismatch now also `print`s the differing fields — a bare `False` in CloudWatch is undebuggable. **The frontend's `MOCK` data in `SubmitPanel.tsx` is written in normal casing and relies on this** — if that stops matching the sample licence, `normalize()` is what broke.

### App API Lambda

- `aws_iam_role.app_api_lambda_role` — assume-role trust for `lambda.amazonaws.com`. Trust-policy `Sid` is the literal `"AppApiLambdaRole"`.
- `aws_iam_role_policy.app_api_lambda_policy` — **inline** policy, the tightest in this module. Three statements: `s3:PutObject` scoped to `${document_s3_bucket_arn}/zipped/*` (the only prefix the handler builds a key for), `kms:GenerateDataKey` on `${document_kms_key_arn}`, and `dynamodb:GetItem` on `${dynamodb_metadata_table_arn}`. **Deliberately absent:** `kms:Decrypt` (never reads an object, and a presigned single PUT is not multipart), `s3:GetObject`/`DeleteObject`/`ListBucket`, Rekognition, Textract, SNS, SQS, X-Ray, and every DynamoDB write action.
- `aws_iam_policy.app_api_lambda_cloudwatch_logs_policy` — **customer-managed** least-privilege CloudWatch policy, same scope pattern as the others.
- `aws_iam_role_policy_attachment.attach_CloudWatchPolicy_to_appApiLambdaRole` — attaches the CW policy to the app API Lambda role.
- `aws_cloudwatch_log_group.app_api_lambda_logs` — `/aws/lambda/<app_api_lambda_function_name>`, 14-day retention.
- `data.archive_file.app_api_lambda_function_archive_file` — zips `src/app_api_lambda.py` to `build/app_api_lambda.zip`.
- `aws_lambda_function.app_api_lambda_function` — Python 3.13, handler `app_api_lambda.lambda_handler`, wired to its log group via `logging_config`. Exposes `BUCKET` and `TABLE` as runtime env vars. No event source of its own — API Gateway invokes it, and that permission is not built yet.

> **The KMS statement is not optional.** The presigned URL is signed with this role's credentials, so the browser's PUT is authorized against this role. The document bucket is SSE-KMS, so without `kms:GenerateDataKey` the upload fails as `AccessDenied` **on the S3 call** — which looks like an S3 permissions problem and isn't.

## Inputs

| Name | Type | Description |
|---|---|---|
| `document_lambda_role_name` | `string` | Full IAM role name (env-suffixed by the caller, e.g. `DocumentLambdaRole-dev`) |
| `document_lambda_policy_name` | `string` | Full inline policy name (env-suffixed) |
| `lambda_cloudwatch_logs_policy_name` | `string` | Full customer-managed CW policy name for the document Lambda (env-suffixed) |
| `document_lambda_function_name` | `string` | Full document Lambda function name (env-suffixed). The function itself is commented out, but this still drives the log group name and CW policy ARN scope — keep it wired. |
| `project_name` | `string` | Project name, used as `POWERTOOLS_SERVICE_NAME` (the X-Ray service label). Same variable that feeds the env's `default_tags`. **Not** env-suffixed — dev and prod would share one service node. |
| `lambda_functions_timeout` | `number` | Max execution time in seconds, shared by all Lambda functions in this module |
| `validate_lambda_function_name` | `string` | Validation Lambda function name (env-suffixed) |
| `validate_lambda_role_name` | `string` | Validation Lambda IAM role name (env-suffixed) |
| `validation_lambda_cloudwatch_logs_policy_name` | `string` | CloudWatch Logs policy name for the validation Lambda (env-suffixed) |
| `current_region` | `string` | Region used to build region-scoped log ARNs (env passes `data.aws_region`) |
| `current_account_id` | `string` | Account ID used to build account-scoped log ARNs (env passes `data.aws_caller_identity`) |
| `document_s3_bucket_arn` | `string` | Bucket ARN — used in the inline S3 policy and as `source_arn` on the invoke permission |
| `document_kms_key_arn` | `string` | ARN of the CMK encrypting the bucket — scopes the `KMSAccessPolicy` statement on the four pipeline roles |
| `document_s3_bucket_name` | `string` | Bucket name — **currently unused**; its only references are the commented-out notification blocks in `document_lambda_function.tf` and `submit_license_lambda_function.tf` |
| `dynamodb_metadata_table_arn` | `string` | DynamoDB table ARN — scoped in the inline policy |
| `dynamodb_document_table_name` | `string` | DynamoDB table **name** — passed to the document Lambda as the `TABLE` environment variable |
| `sns_topic_arn` | `string` | SNS topic ARN — scoped in the inline policy and used as the `TOPIC` env variable |
| `sns_topic_name` | `string` | SNS topic name — passed in but unused at runtime |
| `lambda_rekognition_face_comparison_policy_name` | `string` | Rekognition managed policy name (env-suffixed) |
| `lambda_textract_analyze_id_policy_name` | `string` | Textract managed policy name (env-suffixed by the caller) |
| `validate_license_api_execution_arn` | `string` | execute-api ARN of the validation API — scopes `execute-api:Invoke` for the submit-license role. Comes from `module.api_gateway.validate_license_api_execution_arn`; **not** the API's plain `arn`. |
| `execute_api_submit_license_policy_name` | `string` | Name of the `execute-api:Invoke` managed policy (env-suffixed; hardcoded in `envs/dev/main.tf` rather than tfvars). |
| `submit_license_lambda_function_name` | `string` | Submit-license Lambda function name (env-suffixed). Also drives its log group name and CW policy ARN scope. |
| `submit_license_lambda_role_name` | `string` | Submit-license Lambda IAM role name (env-suffixed) |
| `submit_license_lambda_cloudwatch_logs_policy_name` | `string` | CloudWatch Logs policy name for the submit-license Lambda (env-suffixed) |
| `sqs_submit_license_policy_name` | `string` | SQS poll policy name for the submit-license Lambda (env-suffixed) |
| `sqs_license_queue_arn` | `string` | `LicenseQueue` ARN — scopes the SQS poll policy and is the `event_source_arn` of the event source mapping |
| `sqs_license_queue_name` | `string` | `LicenseQueue` name — passed in for reference |
| `sqs_url` | `string` | `LicenseQueue` URL — passed to the document Lambda as the `SQS_URL` environment variable (the queue it sends the validation message to) |
| `validate_license_api_name` | `string` | API Gateway API name — passed to the submit-license Lambda as the `VALIDATE_LICENSE_API` environment variable |
| `validate_license_api_url` | `string` | API Gateway invoke URL (`POST /license`) — passed to the submit-license Lambda as the `VALIDATE_LICENSE_API_URL` environment variable, used to call the third-party validation endpoint |
| `unzip_lambda_function_name` | `string` | Unzip Lambda function name (env-suffixed by the caller). Also drives its log group name and CW policy ARN scope. |
| `unzip_lambda_function_role_name` | `string` | Unzip Lambda IAM role name (env-suffixed) |
| `unzip_license_lambda_cloudwatch_logs_policy_name` | `string` | CloudWatch Logs policy name for the unzip Lambda (env-suffixed) |
| `write_to_dynamo_lambda_function_name` | `string` | Write-to-DynamoDB Lambda function name (env-suffixed by the caller). Also drives its log group name and CW policy ARN scope. |
| `write_to_dynamo_lambda_function_role_name` | `string` | Write-to-DynamoDB Lambda IAM role name (env-suffixed) |
| `write_to_dynamo_lambda_cloudwatch_logs_policy_name` | `string` | CloudWatch Logs policy name for the write-to-DynamoDB Lambda (env-suffixed) |
| `compare_faces_lambda_function_name` | `string` | Compare-faces Lambda function name (env-suffixed by the caller). Also drives its log group name and CW policy ARN scope. |
| `compare_faces_lambda_function_role_name` | `string` | Compare-faces Lambda IAM role name (env-suffixed) |
| `compare_faces_lambda_cloudwatch_logs_policy_name` | `string` | CloudWatch Logs policy name for the compare-faces Lambda (env-suffixed) |
| `compare_faces_lambda_policy_name` | `string` | Full inline policy name for the compare-faces Lambda (env-suffixed) |
| `compare_details_lambda_function_name` | `string` | Compare-details Lambda function name (env-suffixed by the caller). Also drives its log group name and CW policy ARN scope. |
| `compare_details_lambda_function_role_name` | `string` | Compare-details Lambda IAM role name (env-suffixed) |
| `compare_details_lambda_cloudwatch_logs_policy_name` | `string` | CloudWatch Logs policy name for the compare-details Lambda (env-suffixed) |
| `compare_details_lambda_policy_name` | `string` | Full inline policy name for the compare-details Lambda (env-suffixed) |
| `app_api_lambda_function_name` | `string` | App API Lambda function name (env-suffixed by the caller). Also drives its log group name and CW policy ARN scope. |
| `app_api_lambda_function_role_name` | `string` | App API Lambda IAM role name (env-suffixed) |
| `app_api_lambda_cloudwatch_logs_policy_name` | `string` | CloudWatch Logs policy name for the app API Lambda (env-suffixed) |
| `app_api_lambda_policy_name` | `string` | Full inline policy name for the app API Lambda (env-suffixed) |

## Outputs

| Name | Description |
|---|---|
| `document_lambda_role_arn` | ARN of the Lambda execution role |
| `document_lambda_role_name` | Name of the Lambda execution role |
| `document_lambda_function_arn` | ARN of the Lambda function |
| `document_lambda_function_name` | Name of the Lambda function |
| `validation_lambda_invoke_arn` | Invoke ARN of the validation Lambda — consumed by the apiGateway module's `AWS_PROXY` integration |
| `unzip_lambda_function_arn` / `unzip_lambda_function_name` | Step 1 of the pipeline |
| `write_to_dynamo_lambda_arn` / `write_to_dynamo_lambda_name` | Step 2 of the pipeline |
| `compare_faces_lambda_function_arn` / `compare_faces_lambda_function_name` | Step 3(a) of the pipeline |
| `compare_details_lambda_function_arn` / `compare_details_lambda_function_name` | Step 3(b) of the pipeline |
| `app_api_lambda_invoke_arn` | Invoke ARN of the app API Lambda — for the apiGateway module's `AWS_PROXY` integration. **Nothing consumes it yet.** |
| `app_api_lambda_function_name` | Name of the app API Lambda — for the apiGateway module's `aws_lambda_permission`. **Nothing consumes it yet.** |

The four pipeline outputs are consumed by `modules/stepFunction/` (via the env) — the ARNs become the `Resource` of each state and scope the state machine's `lambda:InvokeFunction` policy.

## Cross-module dependencies

This module consumes values from five sibling modules plus two env-level `data` sources, and feeds the stepFunction module in turn. Everything flows through the env (sub-modules can't reference each other directly):

```
modules/s3/outputs.tf         → document_bucket_arn, document_bucket_name, document_kms_key_arn
modules/dynamodb/outputs.tf   → customer_metadata_table_arn, customer_metadata_table_name
modules/sns/outputs.tf        → sns_topic_arn, sns_topic_name
modules/sqs/outputs.tf        → sqs_license_queue_arn, sqs_url (→ SQS_URL on the document Lambda)
modules/apiGateway/outputs.tf → validate_license_api_name, license_validation_invoke_url
envs/dev/main.tf              → data.aws_caller_identity, data.aws_region
                               → stamps env suffix via local.env_suffix
                               → passes everything into module "document_lambda"
                               → wires customer_metadata_table_name → dynamodb_document_table_name
                               → wires sns_topic_arn → TOPIC env variable on the document, submit-license, compare-faces, and compare-details Lambdas
                               → wires customer_metadata_table_name → TABLE env variable on the write-to-dynamo, compare-faces, and compare-details Lambdas
                               → wires license_validation_invoke_url → validate_license_api_url → VALIDATE_LICENSE_API_URL
modules/lambda/variables.tf   → receives them as var.*
```

**Watch out:** `TOPIC` must resolve to the SNS topic **ARN**, not its name — `sns:Publish` rejects the bare name with `InvalidParameter: TopicArn`.

## Notes

- **`submit_license.py` must `raise`, never `return`, on error.** For an SQS event source mapping, SQS only observes whether the function crashed — a normal return counts as success and the message is deleted, *regardless of the status code in the returned dict*. Returning a 500 made `LicenseQueue`'s `maxReceiveCount = 3` and the whole DLQ unreachable for any failure inside the `try` (the API Gateway call, `update_item`, `sns.publish`). Note the asymmetry this fixed: message parsing (`submit_license.py:22-32`) sits *above* the `try`, so malformed bodies always crashed and redrove correctly — it was the transient, retry-worthy failures that were being silently dropped. Retry is safe here because `update_item` with `SET` is idempotent; the only side effect of a retry is a duplicate SNS email if `publish` succeeded before a later call failed.
- **Presigning against an SSE-KMS bucket requires SigV4, and boto3 does not default to it here.** `boto3.client('s3')` produced a **SigV2** URL (`?AWSAccessKeyId=…&Signature=…&Expires=…`), and the browser's PUT came back `403 InvalidArgument — "Requests specifying Server Side Encryption with AWS KMS managed keys require AWS Signature Version 4."` Nothing fails at signing time: `generate_presigned_url` makes no API call, so the Lambda returns a clean 200 and only the *browser's* upload fails, which reads like an IAM or CORS problem and is neither. The fix is `boto3.client('s3', config=Config(signature_version='s3v4'))` in `app_api_lambda.py`. A correct URL starts `?X-Amz-Algorithm=AWS4-HMAC-SHA256`; if you see `AWSAccessKeyId=`, the config was dropped.
- The `build/` directory holds the zipped Lambda payload generated by `archive_file`. It's gitignored.
- `source_code_hash` is derived from each archive's base64 SHA-256, so any change to a handler in `src/` triggers a redeploy of that function on `terraform apply`.
- **The document Lambda is no longer deployed** — `document_lambda_function.tf` and its two `outputs.tf` entries are commented out in full, so `terraform apply` destroyed the function and its S3 invoke permission. `src/s3_upload.py` and the role/policies/log group all remain, so uncommenting both files restores it. Its logic is superseded by the four-step pipeline.
- **X-Ray tracing fails silently without the IAM grant.** `tracing_config { mode = "Active" }` on its own emits nothing — the function assumes its execution role to call X-Ray, so a missing `xray:*` statement leaves invocations succeeding with no trace data and no error. `tracing_config` and `write_to_dynamo_xray_policy` must be changed together. Same trap as the state machine's own tracing (`modules/stepFunction/README.md`).
- **The Powertools layer must match the runtime.** `AWSLambdaPowertoolsPythonV2:51` (the version in the AWS lab material) declares `python3.7`–`python3.11` and Lambda rejects it against this module's `python3.13`. Verify any replacement with `aws lambda get-layer-version-by-arn --arn <arn>` and read `CompatibleRuntimes` before pinning it.
- Tracing costs cold-start time — the layer unpack/import pushes `Init` to roughly 700ms. Only pay it on functions you actually want to inspect; that's why the other three pipeline Lambdas are untraced.
- `@tracer.capture_lambda_handler` records the handler's return value as trace metadata, and this handler returns `driver_license_id`. Real licence numbers would land in X-Ray, which has different retention and access control than DynamoDB. Pass `capture_response=False` if the data stops being synthetic.
- The unzip/write-to-dynamo/compare-faces/compare-details Lambdas are sequenced by `DocumentStateMachine` in `modules/stepFunction/`, which reacts to `zipped/` uploads via EventBridge. **Don't broaden that prefix** — the unzip handler writes to `unzipped/` in the same bucket, so a wider filter loops.
- The four handlers read each other's output off the state machine's accumulated state (`event['application']['app_uuid']`, etc.), not off a bare payload — a `ResultPath` change in the state machine definition breaks them. See `modules/stepFunction/README.md`.
- `unzip_lambda.py`, `compare_faces_lambda.py`, and `compare_details_lambda.py` all derive selfie/license/details S3 keys as `unzipped/<app_uuid>_selfie.png` / `unzipped/<app_uuid>_license.png` / `unzipped/<app_uuid>_details.csv` — keep them in sync if the upload convention changes.