provider "aws" {
  region = "us-east-1"
}

resource "aws_kms_key" "CreateBucketKey" {
  description             = "KMS key for CreateBucket encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true
}

resource "aws_s3_bucket" "CreateBucket" {
  force_destroy = true
  bucket        = "hx-sec-test${random_string.random_suffix.result}"

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

resource "aws_s3_bucket_logging" "CreateBucketLogging" {
  bucket        = aws_s3_bucket.CreateBucket.id
  target_bucket = aws_s3_bucket.CreateBucket.id
  target_prefix = "log/"
}

resource "aws_s3_bucket_lifecycle_configuration" "CreateBucketLifecycle" {
  bucket = aws_s3_bucket.CreateBucket.id

  rule {
    id     = "default"
    status = "Enabled"

    expiration {
      days = 365
    }
  }
}

resource "aws_s3_bucket_public_access_block" "CreateBucketPublicAccessBlock" {
  bucket = aws_s3_bucket.CreateBucket.id

  block_public_acls      = true
  block_public_policy    = true
  ignore_public_acls     = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_acl" "CreateBucketAcl" {
  bucket     = aws_s3_bucket.CreateBucket.id
  acl        = "private"
  depends_on = [aws_s3_bucket_public_access_block.CreateBucketPublicAccessBlock]
}

resource "aws_s3_bucket_policy" "CreateBucketPolicy" {
  bucket = aws_s3_bucket.CreateBucket.id
  policy = <<EOF
{
	"Version": "2012-10-17",
	"Id": "Policy1650428243041",
	"Statement": [
		{
			"Sid": "EnforceSecureTransport",
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

resource "aws_s3_object" "PutObject_Flag" {
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