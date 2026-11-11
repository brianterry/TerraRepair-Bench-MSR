provider "aws" {
  region = "us-east-1"
}

provider "aws" {
  alias  = "replica"
  region = "us-west-2"
}

resource "aws_kms_key" "s3" {
  description             = "CMK for S3 bucket encryption"
  deletion_window_in_days = 10
  enable_key_rotation     = true
}

resource "aws_kms_key" "s3_replica" {
  provider                = aws.replica
  description             = "CMK for S3 replica bucket encryption"
  deletion_window_in_days = 10
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

resource "aws_s3_bucket" "LogBucket" {
  force_destroy = true
  bucket        = "hxseclablogs${random_string.random_suffix.result}"
}

resource "aws_s3_bucket" "ReplicaBucket" {
  provider      = aws.replica
  force_destroy = true
  bucket        = "hxseclabreplica${random_string.random_suffix.result}"
}

resource "aws_s3_bucket_ownership_controls" "CreateBucketOwnership" {
  bucket = aws_s3_bucket.CreateBucket.id

  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_public_access_block" "CreateBucketPAB" {
  bucket                  = aws_s3_bucket.CreateBucket.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "LogBucketPAB" {
  bucket                  = aws_s3_bucket.LogBucket.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "ReplicaBucketPAB" {
  provider                = aws.replica
  bucket                  = aws_s3_bucket.ReplicaBucket.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_acl" "CreateBucketAcl" {
  depends_on = [
    aws_s3_bucket_ownership_controls.CreateBucketOwnership,
    aws_s3_bucket_public_access_block.CreateBucketPAB
  ]
  bucket = aws_s3_bucket.CreateBucket.id
  acl    = "private"
}

resource "aws_s3_bucket_versioning" "CreateBucketVersioning" {
  bucket = aws_s3_bucket.CreateBucket.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_versioning" "ReplicaBucketVersioning" {
  provider = aws.replica
  bucket   = aws_s3_bucket.ReplicaBucket.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "CreateBucketEncryption" {
  bucket = aws_s3_bucket.CreateBucket.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.s3.arn
      sse_algorithm     = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "LogBucketEncryption" {
  bucket = aws_s3_bucket.LogBucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "ReplicaBucketEncryption" {
  provider = aws.replica
  bucket   = aws_s3_bucket.ReplicaBucket.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.s3_replica.arn
      sse_algorithm     = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_logging" "CreateBucketLogging" {
  bucket        = aws_s3_bucket.CreateBucket.id
  target_bucket = aws_s3_bucket.LogBucket.id
  target_prefix = "log/"
}

resource "aws_s3_bucket_policy" "LogBucketPolicy" {
  bucket = aws_s3_bucket.LogBucket.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3ServerAccessLogsPolicy"
        Effect = "Allow"
        Principal = {
          Service = "logging.s3.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.LogBucket.arn}/*"
        Condition = {
          ArnLike = {
            "aws:SourceArn" = aws_s3_bucket.CreateBucket.arn
          }
        }
      },
      {
        Sid       = "SecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.LogBucket.arn,
          "${aws_s3_bucket.LogBucket.arn}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })
}

resource "aws_s3_bucket_policy" "CreateBucketPolicy" {
  bucket = aws_s3_bucket.CreateBucket.id
  policy = jsonencode({
    Version = "2012-10-17"
    Id      = "HuoXian"
    Statement = [
      {
        Sid       = "SecurityLab"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.CreateBucket.arn,
          "${aws_s3_bucket.CreateBucket.arn}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })
}

resource "aws_s3_bucket_lifecycle_configuration" "CreateBucketLifecycle" {
  bucket = aws_s3_bucket.CreateBucket.id

  rule {
    id     = "expire"
    status = "Enabled"

    expiration {
      days = 365
    }
  }
}

resource "aws_s3_bucket_notification" "CreateBucketNotification" {
  bucket      = aws_s3_bucket.CreateBucket.id
  eventbridge = true
}

resource "aws_iam_role" "replication" {
  name = "hxseclab-repl-${random_string.random_suffix.result}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "s3.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "replication" {
  name = "hxseclab-repl-${random_string.random_suffix.result}"
  role = aws_iam_role.replication.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetReplicationConfiguration",
          "s3:ListBucket"
        ]
        Resource = aws_s3_bucket.CreateBucket.arn
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObjectVersionForReplication",
          "s3:GetObjectVersionAcl",
          "s3:GetObjectVersionTagging",
          "s3:GetObjectRetention",
          "s3:GetObjectLegalHold"
        ]
        Resource = "${aws_s3_bucket.CreateBucket.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ReplicateObject",
          "s3:ReplicateDelete",
          "s3:ReplicateTags"
        ]
        Resource = "${aws_s3_bucket.ReplicaBucket.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey"
        ]
        Resource = aws_kms_key.s3.arn
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Encrypt",
          "kms:GenerateDataKey",
          "kms:DescribeKey"
        ]
        Resource = aws_kms_key.s3_replica.arn
      }
    ]
  })
}

resource "aws_s3_bucket_replication_configuration" "CreateBucketReplication" {
  depends_on = [
    aws_s3_bucket_versioning.CreateBucketVersioning,
    aws_s3_bucket_versioning.ReplicaBucketVersioning
  ]
  role   = aws_iam_role.replication.arn
  bucket = aws_s3_bucket.CreateBucket.id

  rule {
    id       = "replicate-all"
    status   = "Enabled"
    priority = 0

    filter {}

    delete_marker_replication {
      status = "Disabled"
    }

    source_selection_criteria {
      sse_kms_encrypted_objects {
        status = "Enabled"
      }
    }

    destination {
      bucket        = aws_s3_bucket.ReplicaBucket.arn
      storage_class = "STANDARD"

      encryption_configuration {
        replica_kms_key_id = aws_kms_key.s3_replica.arn
      }
    }
  }
}

resource "aws_s3_bucket_object" "PutObject" {
  depends_on = [
    aws_s3_bucket_server_side_encryption_configuration.CreateBucketEncryption
  ]
  bucket                 = aws_s3_bucket.CreateBucket.id
  key                    = "hx.png"
  source                 = "./file/hx.png"
  acl                    = "private"
  content_type           = "image/png"
  server_side_encryption = "aws:kms"
  kms_key_id             = aws_kms_key.s3.arn
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