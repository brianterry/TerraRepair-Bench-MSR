data "aws_region" "current" {}

resource "aws_s3_bucket" "artifacts-k8s-io" {
  bucket = "${var.prefix}artifacts-k8s-io-${data.aws_region.current.name}"
  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        kms_master_key_id = "alias/aws/s3"
        sse_algorithm     = "aws:kms"
      }
    }
  }
  logging {
    target_bucket = "${var.prefix}artifacts-k8s-io-logs-${data.aws_region.current.name}"
    target_prefix = "logs/"
  }
  versioning {
    enabled = true
  }
  replication_configuration {
    role = var.s3_replication_iam_role_arn
    rules = var.s3_replication_rules
  }
  lifecycle_configuration {
    rules = [
      {
        id          = "LifecycleRule1"
        status      = "Enabled"
        expiration  = { days = 30 }
      }
    ]
  }
  event_notification {
    event_types = ["s3:ObjectCreated:*"]
    destination  = {
      type = "SQS"
      queue_arn = "arn:aws:sqs:us-west-2:123456789012:my-queue"
    }
  }
}

resource "aws_s3_bucket_acl" "artifacts-k8s-io" {
  bucket = aws_s3_bucket.artifacts-k8s-io.bucket
  acl    = "private"
}

resource "aws_s3_bucket_public_access_block" "artifacts-k8s-io" {
  bucket = aws_s3_bucket.artifacts-k8s-io.bucket
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "artifacts-k8s-io" {
  bucket = aws_s3_bucket.artifacts-k8s-io.bucket

  rule {
    object_ownership = "BucketOwnerEnforced"
  }

  depends_on = [
    aws_s3_bucket.artifacts-k8s-io,
    aws_s3_bucket_acl.artifacts-k8s-io,
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