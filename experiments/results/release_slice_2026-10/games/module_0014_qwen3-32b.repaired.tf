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
    target_bucket = var.bucket_name
    target_prefix = "logs/"
  }

  lifecycle_rule {
    id      = "default"
    enabled = true

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    expiration {
      days = 365
    }
  }

  replication_configuration {
    role = aws_iam_role.replication_role.arn

    rules {
      id     = "cross_region_replication"
      status = "Enabled"

      destination {
        bucket = aws_s3_bucket.replication_bucket.arn
        storage_class = "STANDARD"
      }
    }
  }

  versioning {
    enabled = true
  }

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "aws:kms"
        kms_master_key_id = aws_kms_key.default.arn
      }
    }
  }

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Deny"
      Principal = "*"
      Action = "s3:PutObject"
      Resource = "${aws_s3_bucket.terraform_state.arn}/*"
      Condition = {
        StringNotEquals = {
          "s3:x-amz-server-side-encryption" = "aws:kms"
        }
      }
    }]
  })
}

resource "aws_s3_bucket" "replication_bucket" {
  bucket = "${var.bucket_name}-replica"
  region = "us-west-2"
}

resource "aws_iam_role" "replication_role" {
  name = "s3_replication_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "s3.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "replication_role_policy" {
  name = "s3_replication_role_policy"
  role = aws_iam_role.replication_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "s3:ReplicateObject",
        "s3:ReplicateDelete",
        "s3:ReplicateTags"
      ]
      Resource = "*"
    }]
  })
}

resource "aws_kms_key" "default" {
  description             = "Default KMS key for S3 and DynamoDB encryption"
  deletion_window_in_days = 10
}

resource "aws_kms_key" "dynamodb" {
  description             = "KMS key for DynamoDB encryption"
  deletion_window_in_days = 10
}

resource "aws_dynamodb_table" "terraform_locks" {
  name         = var.table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  server_side_encryption {
    enabled = true
    kms_key_arn = aws_kms_key.dynamodb.arn
  }

  point_in_time_recovery {
    enabled = true
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