provider "aws" {
  profile = "default"
  region  = "us-west-2"
  alias   = "origin"
}

locals {
  expiration_period = 90
}

data "aws_iam_policy_document" "access_log_policy" {
  statement {
    sid    = "S3ServerAccessLogsPolicy"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["logging.s3.amazonaws.com"]
    }
    actions = [
      "s3:PutObject",
    ]

    resources = ["${aws_s3_bucket.access_log.arn}/*"]

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = [aws_s3_bucket.origin.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values = [
        data.aws_caller_identity.current.id
      ]
    }
  }

  statement {
    principals {
      type        = "Service"
      identifiers = ["logging.s3.amazonaws.com"]
    }
    actions = [
      "s3:GetBucketAcl",
    ]
    resources = [aws_s3_bucket.access_log.arn]
  }
}

resource "aws_s3_bucket" "access_log" {
  provider = aws.origin

  bucket        = "${aws_s3_bucket.origin.bucket}-access-log"
  force_destroy = false

  versioning {
    enabled = true
  }

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "aws:kms"
        kms_master_key_id = "alias/aws/s3"
      }
    }
  }

  depends_on = [
    aws_s3_bucket.origin
  ]
}

resource "aws_s3_bucket_policy" "access_log_policy" {
  bucket = aws_s3_bucket.access_log.id
  policy = data.aws_iam_policy_document.access_log_policy.json
}

resource "aws_s3_bucket_ownership_controls" "access_log" {
  bucket = aws_s3_bucket.access_log.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "access_log" {
  provider = aws.origin

  bucket = aws_s3_bucket.access_log.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "access_log" {
  provider = aws.origin

  bucket = aws_s3_bucket.access_log.id

  rule {
    id     = "auto-delete"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }

    expiration {
      days = local.expiration_period
    }
  }
}

resource "aws_s3_bucket_public_access_block" "access_log" {
  provider = aws.origin

  bucket                  = aws_s3_bucket.access_log.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

data "aws_caller_identity" "current" {
  provider = aws.origin
}

resource "random_pet" "bucket" {
  length = 5
}

data "aws_iam_policy_document" "origin_policy" {
  provider = aws.origin

  statement {
    actions = ["s3:*"]
    effect  = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }

    resources = [
      aws_s3_bucket.origin.arn,
      "${aws_s3_bucket.origin.arn}/*"
    ]

  }

  statement {
    actions = ["s3:GetObject"]
    effect  = "Allow"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    resources = [
      "${aws_s3_bucket.origin.arn}/*"
    ]
  }
}

resource "aws_s3_bucket" "origin" {
  provider = aws.origin

  bucket = "${random_pet.bucket.id}-image-layers"

  versioning {
    enabled = true
  }

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "aws:kms"
        kms_master_key_id = "alias/aws/s3"
      }
    }
  }

  lifecycle_configuration {
    rule {
      id     = "auto-delete"
      status = "Enabled"

      filter {}

      abort_incomplete_multipart_upload {
        days_after_initiation = 7
      }
    }
  }

  public_access_block {
    block_public_acls       = true
    block_public_policy     = true
    ignore_public_acls      = true
    restrict_public_buckets = true
  }
}

resource "aws_s3_bucket_policy" "allow_public_access" {
  provider = aws.origin

  bucket = aws_s3_bucket.origin.id
  policy = data.aws_iam_policy_document.origin_policy.json
}

resource "aws_s3_bucket_cors_configuration" "origin" {
  provider = aws.origin

  bucket                = aws_s3_bucket.origin.id
  expected_bucket_owner = data.aws_caller_identity.current.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "HEAD"]
    allowed_origins = ["*"]
    max_age_seconds = 3000
  }
}

resource "aws_s3_bucket_versioning" "origin" {
  provider = aws.origin

  bucket                = aws_s3_bucket.origin.id
  expected_bucket_owner = data.aws_caller_identity.current.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_ownership_controls" "origin" {
  provider = aws.origin

  bucket = aws_s3_bucket.origin.bucket
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_logging" "origin_access_log" {
  provider = aws.origin

  bucket = aws_s3_bucket.origin.id

  target_bucket = aws_s3_bucket.access_log.id
  target_prefix = ""
}

resource "aws_s3_bucket_notification" "access_log_notification" {
  bucket = aws_s3_bucket.access_log.id

  lambda_function {
    lambda_function_arn = "arn:aws:lambda:us-west-2:123456789012:function:example"
    events              = ["s3:ObjectCreated:*"]
  }
}

resource "aws_s3_bucket_notification" "origin_notification" {
  bucket = aws_s3_bucket.origin.id

  lambda_function {
    lambda_function_arn = "arn:aws:lambda:us-west-2:123456789012:function:example"
    events              = ["s3:ObjectCreated:*"]
  }
}

terraform {
  backend "gcs" {
    bucket = "k8s-infra-tf-aws"
    prefix = "oci-proxy"
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.12.0"
    }
  }
}

terraform {
  required_version = "~> 1.1.2"
}