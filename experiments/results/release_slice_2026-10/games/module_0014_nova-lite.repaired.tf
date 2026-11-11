terraform {
  required_version = ">= 1.0.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  region = "us-east-2"
}

resource "aws_s3_bucket" "terraform_state" {

  bucket = var.bucket_name

  // This is only here so we can destroy the bucket as part of automated tests. You should not copy this for production
  // usage
  force_destroy = true

  logging {
    target_bucket = aws_s3_bucket.terraform_state.id
    target_prefix = "logs/"
  }

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "aws:kms"
        kms_master_key_id = "arn:aws:kms:us-east-2:123456789012:key/abcd1234-a123-456a-a12b-a123b4cd56ef"
      }
    }
  }

  versioning {
    enabled = true
  }

  public_access_block_configuration {
    block_public_acls       = true
    block_public_policy      = true
    ignore_public_acls       = true
    restrict_public_buckets  = true
  }

  lifecycle_rule {
    id      = "logs-retention"
    enabled = true

    expiration {
      days = 365
    }
  }

  replication_configuration {
    role = aws_iam_role.replication_role.arn

    rule {
      id      = "replicate-all"
      enabled = true
      prefix  = ""

      destination {
        bucket = "arn:aws:s3:::destination-bucket"

        storage_class = "STANDARD"
      }
    }
  }

  access_logs {
    target_bucket = aws_s3_bucket.terraform_state.id
    target_prefix = "access-logs/"
  }

  notification_configuration {
    topic_configuration {
      event_types = ["s3:ObjectCreated:*"]
      topic_arn    = aws_sns_topic.terraform_state_notifications.arn
    }
  }
}

resource "aws_s3_bucket_versioning" "enabled" {
  bucket = aws_s3_bucket.terraform_state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "default" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
      kms_master_key_id = "arn:aws:kms:us-east-2:123456789012:key/abcd1234-a123-456a-a12b-a123b4cd56ef"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "public_access" {
  bucket                  = aws_s3_bucket.terraform_state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_dynamodb_table" "terraform_locks" {
  name         = var.table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  point_in_time_recovery_configuration {
    enabled = true
  }

  server_side_encryption_configuration {
    enabled = true
    kms_master_key_id = "arn:aws:kms:us-east-2:123456789012:key/abcd1234-a123-456a-a12b-a123b4cd56ef"
  }

  attribute {
    name = "LockID"
    type = "S"
  }
}

output "s3_bucket_arn" {
  value       = aws_s3_bucket.terraform_state.arn
  description = "The ARN of the S3 bucket"
}

output "dynamodb_table_name" {
  value       = aws_dynamodb_table.terraform_locks.name
  description = "The name of the DynamoDB table"
}

variable "bucket_name" {
  description = "The name of the S3 bucket. Must be globally unique."
  type        = string
}

variable "table_name" {
  description = "The name of the DynamoDB table. Must be unique in this AWS account."
  type        = string
}