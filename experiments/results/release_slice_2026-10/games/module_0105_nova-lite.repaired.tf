provider "aws" {
  region = "us-east-2"
}

resource "aws_s3_bucket" "terraform_state" {
  bucket = "antonputra-terraform-state"

  lifecycle {
    prevent_destroy = true
  }

  versioning {
    enabled = true
  }

  logging {
    target_bucket = "antonputra-terraform-state-logs"
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

  public_access_block_configuration {
    block_public_acls       = true
    block_public_policy     = true
    ignore_public_acls      = true
    restrict_public_buckets = true
  }

  notification_configuration {
    topic_configuration {
      topic_arn = "arn:aws:sns:us-east-2:123456789012:terraform-state-notifications"
      event_types = ["s3:ReducedRedundancyLostObject", "s3:ObjectCreated:*"]
    }
  }

  lifecycle_rule {
    id      = "log-retention"
    enabled = true

    expiration {
      days = 365
    }
  }

  replication_configuration {
    role = "arn:aws:iam::123456789012:role/terraform-state-replication-role"

    rule {
      id      = "replicate-to-us-west-2"
      status  = "Enabled"
      destination {
        bucket = "arn:aws:s3:::antonputra-terraform-state-us-west-2"
      }
    }
  }
}

resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
      kms_master_key_id = "arn:aws:kms:us-east-2:123456789012:key/abcd1234-a123-456a-a12b-a123b4cd56ef"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket                  = aws_s3_bucket.terraform_state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_dynamodb_table" "terraform_state" {
  name         = "terraform-state"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  point_in_time_recovery_configuration {
    enabled = true
  }

  server_side_encryption_configuration {
    encrypted_attributes {
      attribute_name = "LockID"
      encryption_type = "KMS"
    }
  }

  attribute {
    name = "LockID"
    type = "S"
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