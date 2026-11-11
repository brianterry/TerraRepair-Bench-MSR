provider "aws" {
  region = "us-east-1"
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
        sse_algorithm = "aws:kms"
      }
    }
  }
  logging {
    target_bucket = aws_s3_bucket.CreateBucket.id
    target_prefix = "/logs/"
  }
  tags = {
    Name        = "HxCloudLab"
    Environment = "Lab"
  }
}

resource "aws_s3_bucket_public_access_block" "CreateBucketBlock" {
  bucket = aws_s3_bucket.CreateBucket.id
  block_public_acls   = true
  block_public_policy = true
  ignore_public_acls  = true
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
	"Id": "Policy1650428243041",
	"Statement": [
		{
			"Sid": "Stmt1650428241699",
			"Effect": "Allow",
			"Principal": {
				"AWS": "${aws_iam_role.s3_access.arn}"
			},
			      "Action": [
                        "s3:GetObject",
                        "s3:PutObject"
                            ],
			"Resource": [
				"arn:aws:s3:::${aws_s3_bucket.CreateBucket.id}",
                "arn:aws:s3:::${aws_s3_bucket.CreateBucket.id}/*"
			]
		}
	]
}

EOF
}

resource "aws_iam_role" "s3_access" {
  name        = "s3_access"
  description = "Role for S3 access"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "s3.amazonaws.com"
      },
      "Effect": "Allow"
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

resource "aws_s3_bucket_lifecycle_configuration" "lifecycle" {
  bucket = aws_s3_bucket.CreateBucket.id

  rule {
    id = "log"

    filter {
      prefix = "/logs/"
    }

    status = "Enabled"

    expiration {
      days = 90
    }
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