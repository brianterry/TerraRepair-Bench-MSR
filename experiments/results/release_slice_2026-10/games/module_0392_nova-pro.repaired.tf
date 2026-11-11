provider "aws" {
  region = "us-east-1"
}

resource "aws_kms_key" "bucket_key" {
  description             = "KMS key for S3 bucket"
  deletion_window_in_days = 7
}

resource "aws_s3_bucket" "CreateBucket" {
  force_destroy = true
  bucket        = "hx-sec-test${random_string.random_suffix.result}"
  versioning {
    enabled = true
  }
  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm     = "aws:kms"
        kms_master_key_id = aws_kms_key.bucket_key.arn
      }
    }
  }
  logging {
    target_bucket = aws_s3_bucket.CreateBucket.bucket
    target_prefix = "logs/"
  }
  tags = {
    Name        = "HxCloudLab"
    Environment = "Lab"
  }
  lifecycle_rule {
    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }
  }
  replication_configuration {
    role = aws_iam_role.s3_replication.arn

    rules = [{
      id          = "replication-rule"
      status      = "Enabled"
      destination = {
        bucket = "arn:aws:s3:::hx-sec-test-replication${random_string.random_suffix.result}"
      }
      prefix = ""
    }]
  }
  public_access_block_configuration {
    block_public_acls       = true
    block_public_policy     = true
    ignore_public_acls      = true
    restrict_public_buckets = true
  }
}

resource "aws_iam_role" "s3_replication" {
  name = "s3_replication_role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "s3.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.CreateBucket.id

  topic {
    topic_arn = "arn:aws:sns:us-east-1:123456789012:s3-bucket-notifications"
    events    = ["s3:ObjectCreated:*"]
  }
}

resource "random_string" "random_suffix" {
  length  = 5
  special = false
  upper   = false
}

output "AwsCloud_BucketName" {
  description = "S3 Bucket Name"
  value       = "${aws_s3_bucket.CreateBucket.bucket}.s3.us-east-1.amazonaws.com"
}

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "4.10.0"
    }
  }
}