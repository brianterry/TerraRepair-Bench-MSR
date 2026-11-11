provider "aws" {
  region = "us-east-1"
}

resource "aws_kms_key" "huoxian_bucket_key" {
  description             = "KMS key for huoxian_bucket encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true
}

resource "aws_s3_bucket" "huoxian_bucket" {
  force_destroy = true
  bucket        = "houxian${random_string.random_suffix.result}"
}

resource "aws_s3_bucket_versioning" "huoxian_bucket_versioning" {
  bucket = aws_s3_bucket.huoxian_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "huoxian_bucket_encryption" {
  bucket = aws_s3_bucket.huoxian_bucket.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.huoxian_bucket_key.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_logging" "huoxian_bucket_logging" {
  bucket        = aws_s3_bucket.huoxian_bucket.id
  target_bucket = aws_s3_bucket.huoxian_bucket.id
  target_prefix = "log/"
}

resource "aws_s3_bucket_lifecycle_configuration" "huoxian_bucket_lifecycle" {
  bucket = aws_s3_bucket.huoxian_bucket.id

  rule {
    id     = "default-lifecycle-rule"
    status = "Enabled"

    noncurrent_version_expiration {
      noncurrent_days = 365
    }
  }
}

resource "aws_s3_bucket_public_access_block" "huoxian_bucket_public_access_block" {
  bucket = aws_s3_bucket.huoxian_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_acl" "huoxian_bucket_acl" {
  bucket     = aws_s3_bucket.huoxian_bucket.id
  depends_on = [aws_s3_bucket.huoxian_bucket, aws_s3_bucket_public_access_block.huoxian_bucket_public_access_block]
  access_control_policy {
    grant {
      grantee {
        type = "CanonicalUser"
        id   = data.aws_canonical_user_id.current.id
      }
      permission = "FULL_CONTROL"
    }
    owner {
      id = data.aws_canonical_user_id.current.id
    }
  }
}

resource "aws_s3_object" "huoxian_object" {
  bucket = aws_s3_bucket.huoxian_bucket.id
  acl    = "private"
  key    = "flag1650859"
  source = "./flag1650859"
  depends_on = [
    aws_s3_bucket.huoxian_bucket,
  ]
}

resource "random_string" "random_suffix" {
  length  = 5
  special = false
  upper   = false
}

data "aws_canonical_user_id" "current" {}

output "aws_s3_bucket_name" {
  value       = "https://${aws_s3_bucket.huoxian_bucket.bucket}.s3.us-east-1.amazonaws.com"
  description = "This is the bucket name of AWS S3 Service."
}

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "4.10.0"
    }
  }
}