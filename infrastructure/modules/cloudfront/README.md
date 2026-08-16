# `modules/cloudfront`

CloudFront distribution fronting the site bucket with **Origin Access Control (OAC)**, so the bucket is private and the CDN is the only way in. Serves the exported Next.js frontend over HTTPS on a `*.cloudfront.net` domain.

This module owns the OAC, the edge function, the distribution, **and the site bucket's policy** — but not the bucket itself. See `frontend_tutorial.md` §2.5 for the design decisions and the migration order.

## Resources

| Resource | Purpose |
|---|---|
| `aws_cloudfront_origin_access_control.site_oac` | Makes CloudFront sign every origin request SigV4. `signing_behavior = "always"`. This signature is what the bucket policy below checks — the whole mechanism behind "CloudFront can read the bucket, nobody else can". |
| `aws_cloudfront_function.rewrite_uri` | Viewer-request function (`cloudfront-js-2.0`) that rewrites `/login` and `/login/` to `/login/index.html`. Code in `rewrite_uri.js`. |
| `aws_cloudfront_distribution.cdn` | The distribution. `redirect-to-https`, `compress = true`, `PriceClass_100`, default CloudFront certificate. |
| `data.aws_cloudfront_cache_policy.caching_optimized` | `Managed-CachingOptimized` — 24h default TTL, cache key is the URL path plus a normalized `Accept-Encoding`. |
| `data.aws_cloudfront_response_headers_policy.security_headers` | `Managed-SecurityHeadersPolicy` — five security headers, see Footguns. |
| `data.aws_iam_policy_document.s3_site_bucket_policy` | `s3:GetObject` for `cloudfront.amazonaws.com` scoped by `AWS:SourceArn`, plus the standard `AllowSSLRequestsOnly` deny. |
| `aws_s3_bucket_policy.attach_oac_control` | Attaches the above to the site bucket. |

## Inputs

| Name | Type | Description |
|---|---|---|
| `site_bucket_name` | `string` | Site bucket name. Used three ways: the OAC name, the function name prefix, and the bucket id on the policy. From `modules/s3Site`. |
| `site_bucket_arn` | `string` | Site bucket ARN, for the policy's `Resource`. From `modules/s3Site`. |
| `site_bucket_regional_domain_name` | `string` | REST endpoint host (`bucket.s3.<region>.amazonaws.com`) — the origin. Validated to reject an `s3-website-*` host. From `modules/s3Site`. |

## Outputs

| Name | Description |
|---|---|
| `cloudfront_domain_name` | Distribution domain, no scheme. |
| `cloudfront_distribution_id` | Distribution ID — the deploy step's `create-invalidation` needs it. |
| `cloudfront_url` | Full `https://` URL. This is what `local.site_origin` should point at. |

## Footguns

**OAC requires the bucket's REST endpoint, never the website endpoint.** AWS states it directly: OAC "doesn't apply to Amazon S3 origins that you configured as a website endpoint." Website endpoints are anonymous-only and cannot verify a signature, so the private-bucket lock simply doesn't exist there. `site_bucket_regional_domain_name` carries a validation rejecting `s3-website` hosts because the failure mode otherwise is a 403 with no hint at the cause.

**`default_root_object` covers `/` and nothing deeper — that is what `rewrite_uri.js` is for.** The REST endpoint has no index-document behaviour for subdirectories, so `/login/` is passed to S3 as-is and there is no key called `login/`. The function supplies that behaviour at the edge, before the cache lookup. It **depends on `trailingSlash: true` in `frontend/next.config.ts`**, which is what makes the export write `login/index.html` rather than `login.html`. Change one, the other breaks.

**A missing key comes back as 403, not 404.** The bucket policy grants `s3:GetObject` but not `s3:ListBucket`, so S3 will not confirm absence to a caller that cannot list — per AWS: "When the bucket policy for OAC doesn't include the `s3:ListBucket` permission, Amazon S3 returns a 403 error." Both codes are therefore mapped to `/404.html`. **Both keep `response_code = 404`** — do not point them at `/index.html` with a `200`. That is the single-page-app fallback, and on a static export it turns every broken link into a silent home page.

**`Managed-SecurityHeadersPolicy` sets five headers and no CSP.** Verified against the live API: `Strict-Transport-Security: max-age=31536000` (**no `includeSubDomains`, no `preload`** — it protects this host only), `X-Content-Type-Options: nosniff`, `X-Frame-Options: SAMEORIGIN` (not `DENY`), `Referrer-Policy: strict-origin-when-cross-origin`, `X-XSS-Protection: 1; mode=block`. `nosniff` is the only one that overrides what the origin already sent. Content-Security-Policy is deliberately absent — a wrong CSP breaks the site instantly, so AWS leaves it to you.

**`compress = true` and the cache policy are a pair.** Compression only works because `Managed-CachingOptimized` normalizes `Accept-Encoding` into the cache key; without that you would risk serving a gzipped body to a client that never asked for it.

**The bucket policy lives here, not in `modules/s3Site`, on purpose.** The policy needs the distribution ARN and the distribution needs the bucket. Splitting it this way keeps the dependency pointing one direction (`s3Site` → `cloudfront`) instead of the two modules referencing each other. Inside this module the chain is bucket → distribution → policy, which is acyclic because the policy is a separate resource from the bucket.

**Never let two `aws_s3_bucket_policy` resources target the site bucket in one apply.** A bucket has exactly one policy. While `modules/s3Site` still declares `aws_s3_bucket_policy.site_public_read`, the two resources sit at different addresses with no dependency edge between them, so Terraform may create one and destroy the other in either order — and the plan shows nothing wrong. Strip `s3Site` in its own apply *before* this module exists (tutorial §2.5 Step 2).

**Distributions are slow, and `destroy` is the slow half.** Create takes 3–6 minutes; delete takes 5–20 (CloudFront disables, waits for propagation, then deletes). The provider's delete timeout is 90 minutes, so it completes — but do not `Ctrl-C` a `terraform destroy` mid-distribution or you are left reconciling by hand.

**`/*` counts as one path against the 1,000-free-invalidation-paths-per-month allowance**, not as one per object. The deploy step's invalidation is effectively free at this scale.

## Cross-module dependencies

**In:** three values from `modules/s3Site` — bucket name, ARN, and regional domain name.

**Out:** `cloudfront_url` becomes `local.site_origin` in `envs/dev/main.tf`, which feeds **both** CORS allow-lists — the document bucket's (`document_bucket_cors_allow_origins`) and the API's (`api_cors_allow_origins`). Miss either and the site loads over HTTPS but the presigned PUT and every `/api/*` call fail preflight. `cloudfront_distribution_id` feeds the `create-invalidation` in `terraform_data.site_deploy`.

`/api/*` is **not** routed through this distribution — the frontend still calls execute-api directly via `NEXT_PUBLIC_API_BASE`. That keeps the change to the bucket only; proxying the API would need a second origin and a full auth re-test.