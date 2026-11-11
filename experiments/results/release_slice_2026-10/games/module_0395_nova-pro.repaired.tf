provider "aws" {
  region = "us-east-1"
}

resource "aws_kms_key" "bucket_key" {
  description             = "KMS key for S3 bucket"
  deletion_window_in_days = 7
}

resource "aws_s3_bucket" "CreateBucket" {
  force_destroy = true
  bucket        = "hxseclab${random_string.random_suffix.result}"
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
    target_bucket = "hxseclab-logs${random_string.random_suffix.result}"
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
      id          = "hx-replication-rule"
      status      = "Enabled"
      destination = {
        bucket = "arn:aws:s3:::hxseclab-replication${random_string.random_suffix.result}"
      }
      prefix = ""
    }]
  }
}

resource "aws_s3_bucket" "log_bucket" {
  bucket = "hxseclab-logs${random_string.random_suffix.result}"
  versioning {
    enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "CreateBucket" {
  bucket = aws_s3_bucket.CreateBucket.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_acl" "CreateBucketAcl" {
  bucket = aws_s3_bucket.CreateBucket.id
  acl    = "private"
}

resource "aws_s3_bucket_policy" "CreateBucketPolicy" {
  bucket = aws_s3_bucket.CreateBucket.id
  policy = <<EOF
{
    "Version": "2012-10-17",
    "Id": "HuoXian",
    "Statement": [
        {
            "Sid": "SecurityLab",
            "Effect": "Allow",
            "Principal": {
              "AWS": "arn:aws:iam::123456789012:user/example-user"
            },
            "Action": [
                "s3:GetObject",
                "s3:PutObject"
            ],
            "Resource": "arn:aws:s3:::${aws_s3_bucket.CreateBucket.id}/*"
        }
    ]
}
EOF
}

resource "aws_s3_bucket_object" "PutObject" {
  bucket       = aws_s3_bucket.CreateBucket.id
  key          = "hx.png"
  source       = "./file/hx.png"
  acl          = "private"
  server_side_encryption = "aws:kms"
  kms_key_id              = aws_kms_key.bucket_key.arn
  content_type = "image/png"
}

resource "random_string" "random_suffix" {
  length  = 5
  special = false
  upper   = false
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