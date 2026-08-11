# Copyright (c) 2026 Giancarlo Martinez
# SPDX-License-Identifier: Apache-2.0

# KMS ---------------------------------------------------------------------------------
# Customer managed key for the document bucket. The bucket holds PII (selfies, driver's
# licenses), and a CMK buys two things SSE-S3 does not: access to the plaintext is gated
# by KMS permissions on top of S3 permissions, and every use of the key is logged to
# CloudTrail. Cost is $1/mo for the key plus $1/mo each for the first two rotations
# (capped there), plus per-request charges that bucket_key_enabled largely eliminates.
resource "aws_kms_key" "document_key" {
  description = "Encrypts identity documents in the document S3 bucket"

  # New key material every ~365 days. This does NOT create a new key or invalidate old
  # objects: the key ID/ARN never change, old material is retained, and Decrypt picks the
  # right version off the ciphertext automatically. Nothing in this project references it.
  enable_key_rotation = true

  # Only read if a deletion is ever requested - it is the waiting period before AWS
  # destroys the material, not a countdown. Recovery is possible during the window 
  # and impossible after it.
  deletion_window_in_days = 30

  # Deleting this key permanently destroys every object still encrypted with it - there is
  # no recovery path. 
  lifecycle {
    prevent_destroy = true
  }

  # No explicit policy: the default key policy grants the account root kms:*, which is what
  # allows the Lambda roles' IAM policies (step 5) to grant key access. Writing a custom key
  # policy here is how you would make the key policy itself the access control - and also
  # how you lock yourself out.
}

resource "aws_kms_alias" "document_key" {
  # var.document_s3_bucket_name arrives already env-suffixed from the env layer, so dev and
  # prod get distinct alias names in the same account.
  name          = "alias/${var.document_s3_bucket_name}"
  target_key_id = aws_kms_key.document_key.key_id
}