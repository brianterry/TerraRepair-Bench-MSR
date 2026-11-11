data "aws_region" "current" {}

resource "aws_s3_bucket" "artifacts-k8s-io" {
  bucket = "${var.prefix}artifacts-k8s-io-${data.aws_region.current.name}"

  logging {
    target_bucket = var.logging_bucket
    target_prefix = "s3-access-logs/${var.prefix}artifacts-k8s-io-${data.aws_region.current.name}/"
  }
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

resource "aws_s3_bucket_public_access_block" "artifacts-k8s-io" {
  bucket = aws_s3_bucket.artifacts-k8s-io.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "artifacts-k8s-io" {
  bucket = aws_s3_bucket.artifacts-k8s-io.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = var.kms_key_arn
      sse_algorithm     = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_versioning" "artifacts-k8s-io" {
  bucket = aws_s3_bucket.artifacts-k8s-io.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "artifacts-k8s-io" {
  bucket = aws_s3_bucket.artifacts-k8s-io.id

  rule {
    id = "default-lifecycle"

    status = "Enabled"

    noncurrent_version_expiration {
      noncurrent_days = var.noncurrent_version_expiration_days
    }
  }
}

resource "aws_s3_bucket_notification" "artifacts-k8s-io" {
  bucket = aws_s3_bucket.artifacts-k8s-io.id

  dynamic "lambda_function" {
    for_each = var.lambda_function_notifications
    content {
      lambda_function_arn = lambda_function.value.lambda_function_arn
      events              = lambda_function.value.events
      filter_prefix       = lambda_function.value.filter_prefix
      filter_suffix       = lambda_function.value.filter_suffix
    }
  }
}

resource "aws_s3_bucket_replication_configuration" "artifacts-k8s-io" {
  count = length(var.s3_replication_rules) > 0 ? 1 : 0

  depends_on = [aws_s3_bucket_versioning.artifacts-k8s-io]

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

variable "logging_bucket" {
  description = "Bucket for S3 access logs"
  type        = string
}

variable "kms_key_arn" {
  description = "ARN of KMS key for bucket encryption"
  type        = string
}

variable "noncurrent_version_expiration_days" {
  description = "Number of days after which noncurrent versions expire"
  type        = number
  default     = 90
}

variable "lambda_function_notifications" {
  description = "List of Lambda function configurations for bucket notifications"
  type = list(object({
    lambda_function_arn = string
    events              = list(string)
    filter_prefix       = string
    filter_suffix       = string
  }))
  default = []
}

terraform {
  required_version = "~> 1.1"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
}