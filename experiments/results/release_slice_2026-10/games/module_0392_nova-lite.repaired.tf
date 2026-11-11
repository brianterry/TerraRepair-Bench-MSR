provider "aws" {
  region = "us-east-1"
}

resource "aws_s3_bucket" "CreateBucket" {
  force_destroy = true
  bucket        = "hx-sec-test${random_string.random_suffix.result}"

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

  public_access_block_configuration {
    block_public_acls       = true
    block_public_policy     = true
    ignore_public_acls       = true
    restrict_public_buckets = true
  }

  lifecycle_rule {
    id      = "log-storage-rule"
    enabled = true

    expiration {
      days = 365
    }

    noncurrent_version_expiration {
      days = 30
    }
  }

  server_side_encryption_by_default {
    sse_algorithm = "AES256"
  }

  replication_configuration {
    role = aws_iam_role.replication_role.arn

    rule {
      id      = "replicate-all-objects"
      prefix  = ""
      status  = "Enabled"

      destination {
        bucket = "arn:aws:s3:::hx-sec-test-replica"

        storage_class = "STANDARD"
      }
    }
  }

  website {
    index_document = "index.html"
  }

  logging_configuration {
    destination_bucket = "hx-sec-test-logs"
    file_prefix        = "logs/"
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
	"Id": "Policy1650428243041",
	"Statement": [
		{
			"Sid": "Stmt1650428241699",
			"Effect": "Allow",
			"Principal": {
				"AWS": "*"
			},
			"Action": [
				"s3:GetObject",
				"s3:PutObject"
			],
			"Resource": [
				"arn:aws:s3:::${aws_s3_bucket.CreateBucket.id}",
				"arn:aws:s3:::${aws_s3_bucket.CreateBucket.id}/*"
			],
			"Condition": {
				"Bool": {
					"aws:SecureTransport": "true"
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
  acl    = "private"
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