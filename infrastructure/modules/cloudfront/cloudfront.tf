# Copyright (c) 2026 Giancarlo Martinez
# SPDX-License-Identifier: Apache-2.0

locals {
  s3_origin_id = "s3-site"
}

# Managed policies - reference by name so AWS can change the IDs
data "aws_cloudfront_cache_policy" "caching_optimized" {
  name = "Managed-CachingOptimized"
}

# Adds HSTS (Header strict-transport-security) - tells browser to never try HTTP for this host again for a year
# - max-age=31536000 (1 year) and nothing else. NOT includeSubDomains, NOT preload,
#   so it protects this host only. Add them with a custom policy if you ever need them.
# X-Content-Type-Options - nosniff (stops browser guessing a file type from its content)
# X-Frame-Options - SAMEORIGIN (prevents clickjacking/ other pages from iframing login page)
# X-XSS-Protection - 1; mode=block (enables XSS filter)
# Referrer-Policy - controls what goes in Referer header when someone leaves page
#  - Same site → sends the full URL
#  - To another HTTPS site → sends only https://yoursite.com, no path
#  - HTTPS → HTTP → sends nothing
data "aws_cloudfront_response_headers_policy" "security_headers" {
  name = "Managed-SecurityHeadersPolicy"
}

#OAC makes CloudFront sign every origin request with SigV4 which is what
# the bucket policy of this file checks
resource "aws_cloudfront_origin_access_control" "site_oac" {
  name                              = var.site_bucket_name
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

#REST endpoint does not have an index-document behavior for subdirectories.
#Therefore, /login/ never maps to an S3 key. This function rewrites UIR at edge before cache lookup
resource "aws_cloudfront_function" "rewrite_uri" {
  name    = "${var.site_bucket_name}-rewrite_uri"
  runtime = "cloudfront-js-2.0"
  publish = true
  code    = file("${path.module}/rewrite_uri.js")
}


resource "aws_cloudfront_distribution" "cdn" {
  enabled = true #to accept end user requests or not
  comment = var.site_bucket_name
  #handles only "/". the function deals with this to route to login
  default_root_object = "index.html"

  #Use REGIONAL domain name (bucket.s3.us-east-1.amazonaws.com)
  # never the website endpoint since OAC cannot sign to a website endpoint at all
  origin {
    domain_name              = var.site_bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.site_oac.id
    origin_id                = local.s3_origin_id
  }



  default_cache_behavior {
    target_origin_id       = local.s3_origin_id
    viewer_protocol_policy = "redirect-to-https" #http:// on CDN domain upgrades to https by itself
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    #Next.js export's JS bundle drops from a few hundred KB to tens of KB (real difference on a first load),
    #  and CloudFront bills you on bytes transferred out, so you pay for the compressed size.
    #--- It skips files under 1KB and over 10MB, and only compresses content types CloudFront recognizes as text ---
    compress = true #Whether you want CloudFront to automatically compress content for web requests that include Accept-Encoding: gzip in the request header (default: false)

    cache_policy_id            = data.aws_cloudfront_cache_policy.caching_optimized.id
    response_headers_policy_id = data.aws_cloudfront_response_headers_policy.security_headers.id

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.rewrite_uri.arn
    }
  }

  # bucket policy allows s3:GetObject but NOT s3:ListBucket so it can be an access denied
  # giving back a 403 and not 404. Catching error here
  custom_error_response {
    error_code            = 403
    response_code         = 404
    response_page_path    = "/404.html"
    error_caching_min_ttl = 10
  }
  custom_error_response {
    error_code            = 404
    response_code         = 404
    response_page_path    = "/404.html"
    error_caching_min_ttl = 10
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true # *.cloudfront.net cert is free. ACM cert for a custom domain.
  }

  #cheapest price class since is demo
  price_class = "PriceClass_100"
}

#Bucket policy so CloudFront is the only one with access to read the site
data "aws_iam_policy_document" "s3_site_bucket_policy" {
  statement {
    sid       = "AllowCloudFrontOACRead"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${var.site_bucket_arn}/*"]

    principals { #cloudfront can assume it
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    condition { #only assumable if is this exact CloudFront distribution
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.cdn.arn]
    }
  }

  #ENFORCE HTTPS(TLS) connections to bucket attached which will come from CDN
  statement {
    sid       = "AllowSSLRequestsOnly"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [var.site_bucket_arn, "${var.site_bucket_arn}/*"]

    principals {
      identifiers = ["*"]
      type        = "*"
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport" #Tracks whether request is made over HTTPS, if is encrypted then returns true. if unencrypted then false and denies
      values   = ["false"]
    }

  }

}

resource "aws_s3_bucket_policy" "attach_oac_control" {
  bucket = var.site_bucket_name
  policy = data.aws_iam_policy_document.s3_site_bucket_policy.json
}