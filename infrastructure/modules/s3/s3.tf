# Copyright (c) 2026 Giancarlo Martinez
# SPDX-License-Identifier: Apache-2.0

module "document_s3_bucket" {
  source        = "terraform-aws-modules/s3-bucket/aws"
  version       = "5.12.0"
  bucket        = var.document_s3_bucket_name
  force_destroy = true

  # SSE-KMS with the CMK from kms.tf instead of SSE-S3. Server-side means the uploader still
  # sends plaintext over TLS and does nothing special - S3 encrypts on write. Applies to new
  # writes only: objects already stored under AES256 keep decrypting as before.
  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = {
        sse_algorithm     = "aws:kms"
        kms_master_key_id = aws_kms_key.document_key.arn
      }
      # Caches one bucket-level data key instead of calling KMS 
      # per object. Pipeline does several 
      # Get/Put per application, and each would
      # otherwise be a billed KMS request.
      bucket_key_enabled = true
    }
  }

  # This bucket holds PII - selfies and driver's licenses - so the objects are not kept
  # indefinitely. Both prefixes hold the same applicant's documents (zipped/ is the upload,
  # unzipped/ is what the unzip Lambda extracts), so both expire on the same clock.
  # Versioning is deliberately left off: a resubmission reuses the same app_uuid and the
  # newest upload is the correct data, so there is no earlier version worth recovering.
  lifecycle_rule = [
    {
      id      = "expire-uploaded-documents"
      enabled = true
      filter  = { prefix = "zipped/" }
      # Abandoned multipart uploads are invisible in the console but still billed.
      abort_incomplete_multipart_upload_days = 7
      expiration                             = { days = var.document_retention_days }
    },
    {
      id                                     = "expire-extracted-documents"
      enabled                                = true
      filter                                 = { prefix = "unzipped/" }
      abort_incomplete_multipart_upload_days = 7
      expiration                             = { days = var.document_retention_days }
    }
  ]

  #BLOCK PUBLIC ACCESS IS DEFAULT
}

resource "aws_s3_object" "zipped_prefix" {
  bucket = module.document_s3_bucket.s3_bucket_id
  key    = "zipped/"
}

#CORS so browser can PUT the zip file to a presigned URL from the CloudFront origin
resource "aws_s3_bucket_cors_configuration" "document_bucket_cors" {
  bucket = module.document_s3_bucket.s3_bucket_id

  cors_rule {
    allowed_methods = ["PUT"]
    allowed_origins = var.document_bucket_cors_allow_origins # ["https://<cf-domain>", "http://localhost:3000"]
    allowed_headers = ["*"]
    max_age_seconds = var.cors_max_age_seconds
  }
}