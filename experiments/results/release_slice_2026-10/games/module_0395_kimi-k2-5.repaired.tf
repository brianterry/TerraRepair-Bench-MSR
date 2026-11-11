provider "aws" {
  region = "us-east-1"
}

resource "aws_kms_key" "bucket_key" {
  description             = "KMS key for S3 bucket encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true
}

resource "aws_kms_alias" "bucket_key_alias" {
  name          = "alias/s3-bucket-key"
  target_key_id = aws_kms_key.bucket_key.key_id
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
      kms_master_key_id = aws_kms_key.bucket_key.arn
      sse_algorithm     = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "CreateBucketPublicAccessBlock" {
  bucket = aws_s3_bucket.CreateBucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
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
        },
        {
            "Sid": "AllowSecureAccess",
            "Effect": "Allow",
            "Principal": {
                "AWS": "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
            },
            "Action": [
                "s3:GetObject",
                "s3:PutObject"
            ],
            "Resource": "arn:aws:s3:::${aws_s3_bucket.CreateBucket.id}/*",
            "Condition": {
                "Bool": {
                    "aws:SecureTransport": "true"
                }
            }
        }
    ]
}
EOF

  depends_on = [aws_s3_bucket_public_access_block.CreateBucketPublicAccessBlock]
}

data "aws_caller_identity" "current" {}

resource "aws_s3_bucket_object" "PutObject" {
  bucket       = aws_s3_bucket.CreateBucket.id
  key          = "hx.png"
  source       = "./file/hx.png"
  content_type = "image/png"
  kms_key_id   = aws_kms_key.bucket_key.arn
}

resource "aws_s3_bucket_logging" "CreateBucketLogging" {
  bucket = aws_s3_bucket.CreateBucket.id

  target_bucket = aws_s3_bucket.CreateBucket.id
  target_prefix = "logs/"
}

resource "aws_s3_bucket_lifecycle_configuration" "CreateBucketLifecycle" {
  bucket = aws_s3_bucket.CreateBucket.id

  rule {
    id     = "log-lifecycle"
    status = "Enabled"

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    expiration {
      days = 365
    }
  }
}

resource "aws_s3_bucket_notification" "CreateBucketNotification" {
  bucket = aws_s3_bucket.CreateBucket.id

  topic {
    topic_arn     = aws_sns_topic.bucket_notifications.arn
    events        = ["s3:ObjectCreated:*", "s3:ObjectRemoved:*"]
    filter_suffix = ".log"
  }
}

resource "aws_sns_topic" "bucket_notifications" {
  name = "s3-bucket-notifications-${random_string.random_suffix.result}"
}

resource "aws_sns_topic_policy" "bucket_notifications_policy" {
  arn = aws_sns_topic.bucket_notifications.arn
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowS3ToPublish"
        Effect = "Allow"
        Principal = {
          Service = "s3.amazonaws.com"
        }
        Action   = "SNS:Publish"
        Resource = aws_sns_topic.bucket_notifications.arn
        Condition = {
          ArnLike = {
            "aws:SourceArn" = aws_s3_bucket.CreateBucket.arn
          }
        }
      }
    ]
  })
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