/*
Copyright 2022 The Kubernetes Authors.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

resource "aws_s3_bucket" "registry-k8s-io" {
  bucket = "${var.prefix}registry-k8s-io-${data.aws_region.current.name}"
}

resource "aws_s3_bucket_acl" "registry-k8s-io" {
  bucket = aws_s3_bucket.registry-k8s-io.bucket
  acl    = "private"
}

resource "aws_s3_bucket_policy" "registry-k8s-io-public-read" {
  bucket = aws_s3_bucket.registry-k8s-io.bucket

  policy = jsonencode({
    "Id" : "Public-Access",
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Action" : "s3:ListBucket",
        "Effect" : "Allow",
        "Resource" : "${aws_s3_bucket.registry-k8s-io.arn}",
        "Principal" : {
          "AWS" : "${aws_iam_role.s3-replication.arn}"
        }
      },
      {
        "Action" : "s3:GetObject",
        "Effect" : "Allow",
        "Resource" : "${aws_s3_bucket.registry-k8s-io.arn}/*",
        "Principal" : {
          "AWS" : "${aws_iam_role.s3-replication.arn}"
        }
      },
      {
        "Sid" : "AllowSSLRequestsOnly",
        "Action" : "s3:*",
        "Effect" : "Deny",
        "Resource" : "${aws_s3_bucket.registry-k8s-io.arn}/*",
        "Condition" : {
          "Bool" : {
            "aws:SecureTransport" : "false"
          }
        },
        "Principal" : "*"
      }
    ]
  })
}

resource "aws_s3_bucket_ownership_controls" "registry-k8s-io" {
  bucket = aws_s3_bucket.registry-k8s-io.bucket

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
  depends_on = [
    aws_s3_bucket.registry-k8s-io,
    aws_s3_bucket_acl.registry-k8s-io,
    aws_s3_bucket_policy.registry-k8s-io-public-read
  ]
}

resource "aws_s3_bucket_public_access_block" "registry-k8s-io" {
  bucket = aws_s3_bucket.registry-k8s-io.id

  block_public_acls   = true
  block_public_policy = true
  ignore_public_acls  = true
  restrict_public_buckets = true
}

# Versioning must be enabled for S3 replication
resource "aws_s3_bucket_versioning" "registry-k8s-io" {
  bucket = aws_s3_bucket.registry-k8s-io.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "registry-k8s-io" {
  bucket = aws_s3_bucket.registry-k8s-io.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.s3.arn
      sse_algorithm     = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_replication_configuration" "registry-k8s-io" {
  count = length(var.s3_replication_rules) > 0 ? 1 : 0

  # Must have bucket versioning enabled first
  depends_on = [aws_s3_bucket_versioning.registry-k8s-io]

  role = var.s3_replication_iam_role_arn

  bucket = aws_s3_bucket.registry-k8s-io.id

  dynamic "rule" {
    for_each = var.s3_replication_rules

    content {
      id = rule.value.id

      status = rule.value.status

      # Set priority, filter and delete_marker_replication to use V2 schema for multiple 
      # destination bucket rules
      priority = rule.value.priority

      filter {}

      delete_marker_replication {
        status = "Enabled"
      }

      destination {
        bucket        = rule.value.destination_bucket_arn
        storage_class = rule.value.destination_bucket_storage_class

        metrics {
          status = "Enabled"
        }
      }
    }
  }
}

resource "aws_s3_bucket_logging" "registry-k8s-io" {
  bucket = aws_s3_bucket.registry-k8s-io.id

  target_bucket = aws_s3_bucket.registry-k8s-io.id
  target_prefix = "/logs/"
}

resource "aws_s3_bucket_lifecycle_configuration" "registry-k8s-io" {
  bucket = aws_s3_bucket.registry-k8s-io.id

  rule {
    id = "log"

    filter {
      prefix = "/logs/"
    }

    expiration {
      days = 90
    }
  }
}

resource "aws_kms_key" "s3" {
  description             = "KMS key for S3 bucket encryption"
  deletion_window_in_days = 10
}

resource "aws_iam_role" "s3-replication" {
  name        = "s3-replication"
  description = "IAM role for S3 replication"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "s3.amazonaws.com"
        }
      },
    ]
  })
}

data "aws_region" "current" {}

variable "prefix" {
  type    = string
  default = ""
}

variable "s3_replication_iam_role_arn" {
  description = "IAM role assumed by S3 service for replication"
  type        = string
  default     = ""
}

variable "s3_replication_rules" {
  description = "List of maps for S3 replication rules"
  type        = list(map(string))
  default     = []
}