data "aws_region" "current" {}

resource "aws_s3_bucket" "artifacts-k8s-io" {
  bucket = "${var.prefix}artifacts-k8s-io-${data.aws_region.current.name}"
}

resource "aws_s3_bucket_acl" "artifacts-k8s-io" {
  bucket = aws_s3_bucket.artifacts-k8s-io.bucket
  acl = "private"
}

resource "aws_s3_bucket_policy" "artifacts-k8s-io-public-read" {
  bucket = aws_s3_bucket.artifacts-k8s-io.bucket

  policy = jsonencode({
    "Id" : "Public-Access",
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Action" : "s3:ListBucket",
        "Effect" : "Allow",
        "Resource" : aws_s3_bucket.artifacts-k8s-io.arn
        "Principal" : "*"
      },
      {
        "Action" : "s3:GetObject",
        "Effect" : "Allow",
        "Resource" : "${aws_s3_bucket.artifacts-k8s-io.arn}/*",
        "Principal" : "*"
      },
      {
        "Sid" : "RequireTLSForObjectAccess",
        "Action" : "s3:*",
        "Effect" : "Deny",
        "Resource" : "${aws_s3_bucket.artifacts-k8s-io.arn}/*",
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

resource "aws_s3_bucket_ownership_controls" "artifacts-k8s-io" {
  bucket = aws_s3_bucket.artifacts-k8s-io.bucket

  rule {
    object_ownership = "BucketOwnerEnforced"
  }

  depends_on = [
    aws_s3_bucket.artifacts-k8s-io,
    aws_s3_bucket_acl.artifacts-k8s-io,
    aws_s3_bucket_policy.artifacts-k8s-io-public-read
  ]
}

resource "aws_s3_bucket_versioning" "artifacts-k8s-io" {
  bucket = aws_s3_bucket.artifacts-k8s-io.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_replication_configuration" "artifacts-k8s-io" {
  count = length(var.s3_replication_rules) > 0 ? 1 : 0

  role = var.s3_replication_iam_role_arn

  bucket = aws_s3_bucket.artifacts-k8s-io.id

  dynamic "rule" {
    for_each = var.s3_replication_rules

    content {
      id = rule.value.id

      status = rule.value.status

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

  depends_on = [aws_s3_bucket_versioning.artifacts-k8s-io]
}

resource "aws_s3_bucket_public_access_block" "artifacts-k8s-io" {
  bucket = aws_s3_bucket.artifacts-k8s-io.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_logging" "artifacts-k8s-io" {
  bucket = aws_s3_bucket.artifacts-k8s-io.id

  target_bucket = aws_s3_bucket.artifacts-k8s-io.id
  target_prefix = "logs/"
}

resource "aws_s3_bucket_server_side_encryption_configuration" "artifacts-k8s-io" {
  bucket = aws_s3_bucket.artifacts-k8s-io.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.artifacts-k8s-io.arn
      sse_algorithm     = "aws:kms"
    }
  }
}

resource "aws_kms_key" "artifacts-k8s-io" {
  description = "KMS key for S3 bucket artifacts-k8s-io"
}

resource "aws_s3_bucket_notification" "artifacts-k8s-io" {
  bucket = aws_s3_bucket.artifacts-k8s-io.id
}

resource "aws_s3_bucket_lifecycle_configuration" "artifacts-k8s-io" {
  bucket = aws_s3_bucket.artifacts-k8s-io.id

  rule {
    id = "default-lifecycle"

    status = "Enabled"

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    expiration {
      days = 365
    }
  }
}

variable "prefix" {
  description = "Prefix added to bucket name"
  type        = string
  default     = ""
  nullable    = false
}

variable "s3_replication_iam_role_arn" {
  description = "IAM role assumed by S3 service for replication"
  type        = string
  default     = null
}

variable "s3_replication_rules" {
  description = "List of maps for S3 replication rules"
  type        = list(map(string))
  default     = []
  nullable    = false
}

terraform {
  required_version = "~> 1.1"

  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}