provider "aws" {
  region = "us-east-1"
}

data "aws_caller_identity" "current" {}

resource "aws_kms_key" "CreateBucketKey" {
  description             = "KMS key for CreateBucket encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true
}

resource "aws_s3_bucket" "CreateBucket" {
  force_destroy = true
  bucket        = "hxseclab${random_string.random_suffix.result}"

  tags = {
    Name        = "HxCloudLab"
    Environment = "Lab"
  }
}

resource "aws_s3_bucket_versioning" "CreateBucketVersioning" {
  bucket = aws_s3_bucket.CreateBucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "CreateBucketEncryption" {
  bucket = aws_s3_bucket.CreateBucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.CreateBucketKey.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "CreateBucketPublicAccessBlock" {
  bucket = aws_s3_bucket.CreateBucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket" "CreateBucketLogBucket" {
  force_destroy = true
  bucket        = "hxseclab-logs-${random_string.random_suffix.result}"

  tags = {
    Name        = "HxCloudLabLogs"
    Environment = "Lab"
  }
}

resource "aws_s3_bucket_public_access_block" "CreateBucketLogBucketPublicAccessBlock" {
  bucket = aws_s3_bucket.CreateBucketLogBucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "CreateBucketLogBucketVersioning" {
  bucket = aws_s3_bucket.CreateBucketLogBucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "CreateBucketLogBucketEncryption" {
  bucket = aws_s3_bucket.CreateBucketLogBucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.CreateBucketKey.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_logging" "CreateBucketLogging" {
  bucket        = aws_s3_bucket.CreateBucket.id
  target_bucket = aws_s3_bucket.CreateBucketLogBucket.id
  target_prefix = "log/"
}

resource "aws_s3_bucket_lifecycle_configuration" "CreateBucketLifecycle" {
  bucket = aws_s3_bucket.CreateBucket.id

  rule {
    id     = "default-lifecycle"
    status = "Enabled"

    noncurrent_version_expiration {
      noncurrent_days = 90
    }

    expiration {
      days = 365
    }
  }
}

resource "aws_s3_bucket_acl" "CreateBucketAcl" {
  bucket = aws_s3_bucket.CreateBucket.id
  acl    = "private"

  depends_on = [aws_s3_bucket_public_access_block.CreateBucketPublicAccessBlock]
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
                "AWS": "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
            },
            "Action": [
                "s3:GetObjectAcl",
                "s3:PutObjectAcl"
            ],
            "Resource": "arn:aws:s3:::${aws_s3_bucket.CreateBucket.id}/*"
        },
        {
            "Sid": "DenyInsecureTransport",
            "Effect": "Deny",
            "Principal": "*",
            "Action": "s3:*",
            "Resource": [
                "arn:aws:s3:::${aws_s3_bucket.CreateBucket.id}",
                "arn:aws:s3:::${aws_s3_bucket.CreateBucket.id}/*"
            ],
            "Condition": {
                "Bool": {
                    "aws:SecureTransport": "false"
                }
            }
        }
    ]
}
EOF
}

resource "aws_s3_object" "PutObject" {
  bucket = aws_s3_bucket.CreateBucket.id
  key    = "flag.txt"
  source = "./flag.txt"
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