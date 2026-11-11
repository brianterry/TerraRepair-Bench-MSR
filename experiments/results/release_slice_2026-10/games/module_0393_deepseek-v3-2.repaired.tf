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
                "AWS": "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
            },
            "Action": [
                "s3:GetObjectAcl",
                "s3:PutObjectAcl"
            ],
            "Resource": "arn:aws:s3:::${aws_s3_bucket.CreateBucket.id}/*"
        }
    ]
}
EOF
}

resource "aws_s3_bucket_versioning" "CreateBucket" {
  bucket = aws_s3_bucket.CreateBucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_logging" "CreateBucket" {
  bucket = aws_s3_bucket.CreateBucket.id
  target_bucket = aws_s3_bucket.CreateBucket.id
  target_prefix = "logs/"
}

resource "aws_s3_bucket_server_side_encryption_configuration" "CreateBucket" {
  bucket = aws_s3_bucket.CreateBucket.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.CreateBucket.arn
      sse_algorithm     = "aws:kms"
    }
  }
}

resource "aws_kms_key" "CreateBucket" {
  description             = "KMS key for S3 bucket encryption"
  deletion_window_in_days = 10
  enable_key_rotation    = true
}

resource "aws_s3_bucket_lifecycle_configuration" "CreateBucket" {
  bucket = aws_s3_bucket.CreateBucket.id

  rule {
    id     = "default"
    status = "Enabled"

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 90
      storage_class = "GLACIER"
    }
  }
}

resource "aws_s3_bucket_replication_configuration" "CreateBucket" {
  depends_on = [aws_s3_bucket_versioning.CreateBucket]
  bucket = aws_s3_bucket.CreateBucket.id
  role   = aws_iam_role.replication.arn

  rule {
    id     = "default"
    status = "Enabled"

    destination {
      bucket        = aws_s3_bucket.replica.arn
      storage_class = "STANDARD"
    }
  }
}

resource "aws_s3_bucket" "replica" {
  bucket = "hxseclab-replica${random_string.random_suffix.result}"
}

resource "aws_iam_role" "replication" {
  name = "s3-replication-role"

  assume_role_policy = <<POLICY
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
POLICY
}

resource "aws_iam_policy" "replication" {
  name = "s3-replication-policy"

  policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "s3:GetReplicationConfiguration",
        "s3:ListBucket"
      ],
      "Effect": "Allow",
      "Resource": [
        "${aws_s3_bucket.CreateBucket.arn}"
      ]
    },
    {
      "Action": [
        "s3:GetObjectVersionForReplication",
        "s3:GetObjectVersionAcl",
        "s3:GetObjectVersionTagging"
      ],
      "Effect": "Allow",
      "Resource": [
        "${aws_s3_bucket.CreateBucket.arn}/*"
      ]
    },
    {
      "Action": [
        "s3:ReplicateObject",
        "s3:ReplicateDelete",
        "s3:ReplicateTags"
      ],
      "Effect": "Allow",
      "Resource": "${aws_s3_bucket.replica.arn}/*"
    }
  ]
}
POLICY
}

resource "aws_iam_role_policy_attachment" "replication" {
  role       = aws_iam_role.replication.name
  policy_arn = aws_iam_policy.replication.arn
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

data "aws_caller_identity" "current" {}

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