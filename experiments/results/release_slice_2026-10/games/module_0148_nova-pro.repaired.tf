data "aws_iam_policy_document" "access_log_policy" {
  statement {
    actions = ["s3:*"]
    effect  = "Deny"
    resources = [
      aws_s3_bucket.access_log.arn,
      "${aws_s3_bucket.access_log.arn}/*"
    ]
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
    principals {
      type        = "*"
      identifiers = ["*"]
    }
  }
}

resource "aws_s3_bucket" "access_log" {
  bucket        = var.log_bucket_name
  force_destroy = var.force_destroy
  versioning {
    enabled = true
  }
  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm   = "aws:kms"
        kms_master_key_id = "alias/aws/s3"
      }
    }
  }
  tags = var.tags
}

resource "aws_s3_bucket_acl" "access_log" {
  bucket = aws_s3_bucket.access_log.id
  acl    = "log-delivery-write"
}

resource "aws_s3_bucket_server_side_encryption_configuration" "access_log" {
  bucket = aws_s3_bucket.access_log.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm   = "aws:kms"
      kms_master_key_id = "alias/aws/s3"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "access_log" {
  count = var.lifecycle_glacier_transition_days > 0 ? 1 : 0

  bucket = aws_s3_bucket.access_log.id

  rule {
    id     = "auto-archive"
    status = "Enabled"

    filter {}

    transition {
      days          = var.lifecycle_glacier_transition_days
      storage_class = "GLACIER"
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

resource "aws_s3_bucket_policy" "access_log_policy" {
  bucket = aws_s3_bucket.access_log.id
  policy = data.aws_iam_policy_document.access_log_policy.json

  depends_on = [
    aws_s3_bucket_public_access_block.access_log,
  ]
}

resource "aws_s3_bucket_public_access_block" "access_log" {
  bucket                  = aws_s3_bucket.access_log.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket" "content" {
  bucket        = var.bucket_name
  force_destroy = var.force_destroy
  versioning {
    enabled = true
  }
  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm   = "aws:kms"
        kms_master_key_id = "alias/aws/s3"
      }
    }
  }
  tags = var.tags

  depends_on = [
    aws_s3_bucket_public_access_block.access_log
  ]
}

resource "aws_s3_bucket_acl" "content" {
  bucket = aws_s3_bucket.content.id
  acl    = "private"
}

resource "aws_s3_bucket_server_side_encryption_configuration" "content" {
  bucket = aws_s3_bucket.content.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm   = "aws:kms"
      kms_master_key_id = "alias/aws/s3"
    }
    bucket_key_enabled = var.bucket_key_enabled
  }
}

resource "aws_s3_bucket_logging" "content" {
  bucket = aws_s3_bucket.content.id

  target_bucket = aws_s3_bucket.access_log.id
  target_prefix = ""
}

resource "aws_s3_bucket_lifecycle_configuration" "content" {
  count = var.lifecycle_glacier_transition_days > 0 ? 1 : 0

  bucket = aws_s3_bucket.content.id

  rule {
    id     = "auto-archive"
    status = "Enabled"

    filter {}

    transition {
      days          = var.lifecycle_glacier_transition_days
      storage_class = "GLACIER"
    }

    noncurrent_version_transition {
      noncurrent_days = var.lifecycle_glacier_transition_days
      storage_class   = "GLACIER"
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

resource "aws_s3_bucket_versioning" "content" {
  bucket = aws_s3_bucket.content.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "content" {
  bucket                  = aws_s3_bucket.content.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_notification" "access_log" {
  bucket = aws_s3_bucket.access_log.id

  topic {
    event_types = ["s3:ObjectCreated:*"]
    topic_arn   = var.sns_topic_arn
  }
}

resource "aws_s3_bucket_notification" "content" {
  bucket = aws_s3_bucket.content.id

  topic {
    event_types = ["s3:ObjectCreated:*"]
    topic_arn   = var.sns_topic_arn
  }
}

variable "sns_topic_arn" {
  description = "The ARN of the SNS topic to notify for bucket events."
  type        = string
}

output "this_bucket" {
  description = "This S3 bucket."
  value       = aws_s3_bucket.content
}

output "log_bucket" {
  description = "The S3 bucket used for storing access logs of this bucket."
  value       = aws_s3_bucket.access_log
}

terraform {
  required_version = ">= 0.13"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 4.3"
    }
  }
}