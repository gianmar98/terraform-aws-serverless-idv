# S3 Module

Provisions the document storage S3 bucket, its KMS customer managed key, and a TLS-only bucket policy.

## Resources

- `module.document_s3_bucket` — `terraform-aws-modules/s3-bucket/aws` v5.12.0
  - **SSE-KMS** with the CMK below, `bucket_key_enabled = true`
  - Public access blocked (the upstream module's default)
  - `force_destroy = true` — `terraform destroy` will empty the bucket before deleting it, so it won't fail with `BucketNotEmpty`
  - **Two lifecycle rules** (`expire-uploaded-documents`, `expire-extracted-documents`) expiring `zipped/` and `unzipped/` objects after `var.document_retention_days` (default 30), plus `abort_incomplete_multipart_upload_days = 7` on both. The bucket holds PII — selfies and driver's licenses — so documents aren't retained indefinitely.
  - **Versioning is deliberately off.** A resubmission reuses the same `app_uuid`, so the newest upload *is* the correct data and there's no earlier version worth recovering. Enabling it is also irreversible (it can only be suspended, never removed).
- `aws_kms_key.document_key` / `aws_kms_alias.document_key` — customer managed key encrypting the bucket. `enable_key_rotation = true`, `deletion_window_in_days = 30`. The `lifecycle { prevent_destroy = true }` block is **commented out** — it blocked `terraform destroy`, and this project's goal is one `apply` up / one `destroy` down. Uncomment it for anything holding real data. No explicit key policy, so the default (account root gets `kms:*`) applies and the Lambda roles' IAM policies are what actually grant access.
- `aws_s3_bucket_policy.document_bucket_tls_only` — denies any non-HTTPS request (`aws:SecureTransport = false`)
- `aws_s3_object.zipped_prefix` — empty `zipped/` placeholder object so the prefix exists in the console before the first upload. Uploads under that prefix are what start the pipeline (via the EventBridge rule in `modules/stepFunction/`).
- `aws_s3_bucket_cors_configuration.document_bucket_cors` — allows `PUT` from `var.document_bucket_cors_allow_origins` so the browser can upload the zip straight to a presigned URL. Any header is allowed (`["*"]`); no `expose_headers`, because the frontend doesn't read the PUT response.

## Inputs

| Name | Type | Description |
|---|---|---|
| `document_s3_bucket_name` | `string` | Name of the document S3 bucket |
| `document_retention_days` | `number` | Days after upload that `zipped/`/`unzipped/` objects expire. Set per-env in `envs/dev/terraform.tfvars`; falls back to `30` if the caller omits it. Validated `> 0`. |
| `document_bucket_cors_allow_origins` | `list(string)` | Origins allowed to presign-PUT to the bucket. Required (no default). Passed inline from `envs/dev/main.tf` as `["http://localhost:3000", local.site_origin]`, not a tfvars dial — `local.site_origin` is the S3 website endpoint of `modules/s3Site`. The CloudFront domain joins the list once it exists |
| `cors_max_age_seconds` | `number` | How long a browser may cache the CORS preflight. Set in `envs/dev/terraform.tfvars` (`300`) and shared with `modules/apiGateway`'s `cors_configuration.max_age` |

## Outputs

| Name | Description |
|---|---|
| `document_bucket_name` | Name (ID) of the document S3 bucket |
| `document_bucket_arn` | ARN of the document S3 bucket — consumed by the lambda module via the env |
| `document_bucket_regional_domain_name` | Regional domain name of the bucket |
| `document_bucket_id` | Bucket ID — consumed by the stepFunction module, which attaches the bucket's EventBridge notification |
| `document_kms_key_arn` | ARN of the CMK — consumed by the lambda module via the env, where it scopes the `KMSAccessPolicy` statement on the four pipeline roles |

## Notes

- Bucket names are globally unique across AWS — pick something distinctive in `terraform.tfvars`.
- For the AWS S3 bucket module, `s3_bucket_id` equals the bucket name — `document_bucket_id` and `document_bucket_name` are the same value under two names.
- **Objects here are deleted after 30 days by default.** That's the point of the lifecycle rules, but it means a demo zip uploaded more than a month ago will be gone. Raise `document_retention_days` if you need sample data to persist.
- **CORS is not a permission.** The rule only tells the browser the cross-origin PUT is allowed; the presigned URL's signature is what actually authorizes the write. Adding an origin here grants nothing on its own, and forgetting one fails in devtools as a CORS error while the same PUT from `curl` (no `Origin` header) succeeds.
- **This module does not define the bucket's notification config.** `modules/stepFunction/` owns it (`eventbridge = true`), and a bucket accepts only one — don't add a second here.
- **`s3:GetObject` is no longer sufficient to read an object.** Once the bucket is SSE-KMS, any role reading objects also needs `kms:Decrypt` on the CMK, and any role writing them needs `kms:GenerateDataKey`. Missing the KMS half surfaces as `AccessDenied` on the S3 call, which reads like an S3 permissions problem and isn't. The four pipeline roles are granted in `modules/lambda/lambda_policies.tf`.
- **Rekognition and Textract read these objects with the *calling Lambda's* credentials**, not a service principal of their own. That's why the CMK needs no `rekognition.amazonaws.com` / `textract.amazonaws.com` entry in its key policy — `kms:Decrypt` on the compare-faces and compare-details roles is what makes those calls work.
- **Changing default encryption only affects new writes.** Objects written before this change are still SSE-S3 and still readable; nothing is re-encrypted.
- **Deleting the CMK permanently destroys every object still encrypted with it.** `prevent_destroy` is commented out, so `terraform destroy` now schedules the key for deletion instead of failing on it. That's deliberate — the bucket is `force_destroy` anyway, so a teardown was always going to take the documents with it. The consequence to know: **each destroy/apply cycle creates a brand-new CMK**, so anything encrypted by an earlier key is unreadable even if you copied the objects out first. Uncomment the block before this holds data you care about.
- Rotation is invisible to this project: it adds new key material inside the same key (same ID, ARN, and alias) and retains old material, so previously written objects keep decrypting. Cost is $1/mo for the key plus $1/mo each for the first two rotations, capped there.