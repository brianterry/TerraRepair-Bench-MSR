provider "aws" {
  region = "us-east-2"
}

resource "aws_s3_bucket" "terraform_state" {
  bucket = "antonputra-terraform-state"

  lifecycle {
    prevent_destroy = true
  }

  logging {
    target_bucket = "antonputra-terraform-state-logs"
    target_prefix = "logs/"
  }

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

  replication_configuration {
    role = aws_iam_role.s3_replication.arn

    rules = [
      {
        id          = "replication-rule"
        status      = "Enabled"
        destination {
          bucket = "arn:aws:s3:::antonputra-terraform-state-replication"
        }
        prefix_predicate = ""
      },
    ]
  }

  lifecycle_configuration {
    rules = [
      {
        id      = "LifecycleRule"
        enabled = true
        expiration {
          days = 30
        }
      },
    ]
  }
}

resource "aws_iam_role" "s3_replication" {
  name = "s3_replication_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "s3.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_s3_bucket_notification" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  topic {
    topic_arn = "arn:aws:sns:us-east-2:123456789012:example-topic"
    events    = ["s3:ObjectCreated:*"]
  }
}

resource "aws_kms_key" "dynamodb_key" {
  description             = "KMS key for DynamoDB"
  deletion_window_in_days = 7
}

resource "aws_dynamodb_table" "terraform_state" {
  name         = "terraform-state"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled = true
    kms_key_arn = aws_kms_key.dynamodb_key.arn
  }
}

terraform {
  backend "s3" {
    key = "global/s3/terraform.tfstate"
  }
}

output "s3_bucket_arn" {
  value       = aws_s3_bucket.terraform_state.arn
  description = "The ARN of the S3 bucket"
}

output "dynamodb_table_name" {
  value       = aws_dynamodb_table.terraform_state.name
  description = "The name of the DynamoDB table"
}