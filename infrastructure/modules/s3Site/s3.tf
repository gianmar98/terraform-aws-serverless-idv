# Copyright (c) 2026 Giancarlo Martinez
# SPDX-License-Identifier: Apache-2.0

resource "aws_s3_bucket" "site" {
  bucket = var.site_bucket_name
  //full site will be generated with "bun run build" so its okay to destroy
  force_destroy = true
}

resource "aws_s3_bucket_website_configuration" "site" {
  bucket = aws_s3_bucket.site.id

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "404.html"
  }
}

//Public bucket to show site to public
resource "aws_s3_bucket_public_access_block" "site_public_access" {
  bucket = aws_s3_bucket.site.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false

}

data "aws_iam_policy_document" "site_public_read" {
  statement {
    sid       = "PublicReadGetObject"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.site.arn}/*"]

    principals {
      identifiers = ["*"]
      type        = "*"
    }
    //Website endpoint is HTTP, denying non-TLS requests here would deny every
    // request on the site
  }
}

//attach get object policy on site bucket
resource "aws_s3_bucket_policy" "site_public_read" {
  bucket = aws_s3_bucket.site.id
  policy = data.aws_iam_policy_document.site_public_read.json

  //make sure its made after
  depends_on = [aws_s3_bucket_public_access_block.site_public_access]
}