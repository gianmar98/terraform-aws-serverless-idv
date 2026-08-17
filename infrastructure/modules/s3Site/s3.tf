# Copyright (c) 2026 Giancarlo Martinez
# SPDX-License-Identifier: Apache-2.0

resource "aws_s3_bucket" "site" {
  bucket = var.site_bucket_name
  #full site will be generated with "bun run build" so its okay to destroy
  force_destroy = true
}

#Off because OAC cannot sign to a website endpoint. CloudFront reads the REST endpoint
# instead, and its edge function is what maps /login/ to login/index.html now
# resource "aws_s3_bucket_website_configuration" "site" {
#   bucket = aws_s3_bucket.site.id
#
#   index_document {
#     suffix = "index.html"
#   }
#
#   error_document {
#     key = "404.html"
#   }
# }

#Private bucket, only CloudFront can read it. The policy that allows it lives in modules/cloudfront
resource "aws_s3_bucket_public_access_block" "site_public_access" {
  bucket = aws_s3_bucket.site.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true

}

#Replaced by the OAC policy in modules/cloudfront. Leaving this here would break things
# since a bucket only holds ONE policy, so two of them fight and whichever applies
# last wins. The depends_on went with it, it only existed because you cannot
# attach a public policy while block_public_policy is on, and the new one is not public
# data "aws_iam_policy_document" "site_public_read" {
#   statement {
#     sid       = "PublicReadGetObject"
#     actions   = ["s3:GetObject"]
#     resources = ["${aws_s3_bucket.site.arn}/*"]
#
#     principals {
#       identifiers = ["*"]
#       type        = "*"
#     }
#   }
# }

# resource "aws_s3_bucket_policy" "site_public_read" {
#   bucket = aws_s3_bucket.site.id
#   policy = data.aws_iam_policy_document.site_public_read.json
#
#   depends_on = [aws_s3_bucket_public_access_block.site_public_access]
# }