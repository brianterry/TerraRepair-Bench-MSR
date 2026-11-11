provider "aws" {
  region = "us-east-1"
}

resource "aws_s3_bucket" "CreateBucket" {
  force_destroy = true
  bucket        = "hxseclab${random_string.random_suffix.result}"

  tags = {
    Name        = "HxCloudLab"
    Environment = "Lab"
  }

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

  logging {
    target_bucket = self.id
    target_prefix = "log/"
  }
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
            "Effect": "Deny",
            "Principal": "*",
            "Action": [
                "s3:PutObject",
                "s3:GetObject"
            ],
            "Resource": "arn:aws:s3:::${aws_s3_bucket.CreateBucket.id}/*",
            "Condition": {
                "StringNotLike": {
                    "aws:arn": [
                        "arn:aws:iam::123456789012:user/SecureUser"
                    ]
                }
            }
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
  content_type = "image/png"
  server_side_encryption = "aws:kms"
  kms_key_id = "alias/aws/s3"
}

resource "aws_s3_bucket_public_access_block" "CreateBucketAccessBlock" {
  bucket = aws_s3_bucket.CreateBucket.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
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

resource "aws_s3_bucket_lifecycle_configuration" "CreateBucketLifecycle" {
  bucket = aws_s3_bucket.CreateBucket.id

  rule {
    name    = "ExpireOldObjects"
    enabled = true

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    expiration {
      days = 90
    }

    filter {
      prefix = "log/"
    }
  }
}

resource "aws_s3_bucket_replication_configuration" "CreateBucketReplication" {
  bucket = aws_s3_bucket.CreateBucket.id

  role = "arn:aws:iam::123456789012:role/ReplicationRole"

  rules {
    id     = "ReplicateToEU"
    status = "Enabled"

    destination {
      bucket_arn = "arn:aws:s3:::hxseclab-replica"
      storage_class = "STANDARD"
    }

    filter {
      prefix = "log/"
    }
  }
}

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "4.10.0"
    }
  }
}