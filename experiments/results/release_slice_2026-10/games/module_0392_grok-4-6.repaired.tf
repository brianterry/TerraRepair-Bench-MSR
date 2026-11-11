provider "aws" {
  region = "us-east-1"
}

provider "aws" {
  alias  = "replica"
  region = "us-west-2"
}

resource "aws_s3_bucket" "CreateBucket" {
  force_destroy = true
  bucket        = "hx-sec-test${random_string.random_suffix.result}"

  tags = {
    Name        = "HxCloudLab"
    Environment = "Lab"
  }
}

resource "aws_s3_bucket_ownership_controls" "CreateBucket" {
  bucket = aws_s3_bucket.CreateBucket.id

  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_acl" "CreateBucketAcl" {
  bucket     = aws_s3_bucket.CreateBucket.id
  acl        = "private"
  depends_on = [aws_s3_bucket_ownership_controls.CreateBucket]
}

resource "aws_s3_bucket_public_access_block" "CreateBucket" {
  bucket = aws_s3_bucket.CreateBucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "CreateBucket" {
  bucket = aws_s3_bucket.CreateBucket.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_kms_key" "CreateBucket" {
  description             = "Customer managed key for S3 encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "CreateBucket" {
  bucket = aws_s3_bucket.CreateBucket.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.CreateBucket.arn
      sse_algorithm     = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket" "CreateBucketLogs" {
  force_destroy = true
  bucket        = "hx-sec-test${random_string.random_suffix.result}-logs"
}

resource "aws_s3_bucket_public_access_block" "CreateBucketLogs" {
  bucket = aws_s3_bucket.CreateBucketLogs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "CreateBucketLogs" {
  bucket = aws_s3_bucket.CreateBucketLogs.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "CreateBucketLogs" {
  bucket = aws_s3_bucket.CreateBucketLogs.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.CreateBucket.arn
      sse_algorithm     = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "CreateBucketLogs" {
  bucket = aws_s3_bucket.CreateBucketLogs.id

  rule {
    id     = "cleanup"
    status = "Enabled"

    filter {
      prefix = ""
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }

    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }
}

resource "aws_s3_bucket_policy" "CreateBucketLogs" {
  bucket = aws_s3_bucket.CreateBucketLogs.id
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
        Resource = "${aws_s3_bucket.CreateBucketLogs.arn}/log/*"
        Condition = {
          ArnLike = {
            "aws:SourceArn" = aws_s3_bucket.CreateBucket.arn
          }
        }
      },
      {
        Sid       = "AllowSSLRequestsOnly"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.CreateBucketLogs.arn,
          "${aws_s3_bucket.CreateBucketLogs.arn}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })
  depends_on = [aws_s3_bucket_public_access_block.CreateBucketLogs]
}

resource "aws_s3_bucket_logging" "CreateBucket" {
  bucket        = aws_s3_bucket.CreateBucket.id
  target_bucket = aws_s3_bucket.CreateBucketLogs.id
  target_prefix = "log/"
  depends_on    = [aws_s3_bucket_policy.CreateBucketLogs]
}

resource "aws_s3_bucket_lifecycle_configuration" "CreateBucket" {
  bucket = aws_s3_bucket.CreateBucket.id

  rule {
    id     = "cleanup"
    status = "Enabled"

    filter {
      prefix = ""
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }

    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }
}

resource "aws_s3_bucket_policy" "CreateBucketPolicy" {
  bucket = aws_s3_bucket.CreateBucket.id
  policy = jsonencode({
    Version = "2012-10-17"
    Id      = "Policy1650428243041"
    Statement = [
      {
        Sid       = "AllowSSLRequestsOnly"
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
  depends_on = [aws_s3_bucket_public_access_block.CreateBucket]
}

resource "aws_s3_bucket" "CreateBucketReplica" {
  provider      = aws.replica
  force_destroy = true
  bucket        = "hx-sec-test${random_string.random_suffix.result}-replica"
}

resource "aws_s3_bucket_public_access_block" "CreateBucketReplica" {
  provider = aws.replica
  bucket   = aws_s3_bucket.CreateBucketReplica.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "CreateBucketReplica" {
  provider = aws.replica
  bucket   = aws_s3_bucket.CreateBucketReplica.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_kms_key" "CreateBucketReplica" {
  provider                = aws.replica
  description             = "Customer managed key for S3 replica encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "CreateBucketReplica" {
  provider = aws.replica
  bucket   = aws_s3_bucket.CreateBucketReplica.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.CreateBucketReplica.arn
      sse_algorithm     = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "CreateBucketReplica" {
  provider = aws.replica
  bucket   = aws_s3_bucket.CreateBucketReplica.id

  rule {
    id     = "cleanup"
    status = "Enabled"

    filter {
      prefix = ""
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }

    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }
}

resource "aws_iam_role" "CreateBucketReplication" {
  name = "s3-repl-${random_string.random_suffix.result}"

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

resource "aws_iam_role_policy" "CreateBucketReplication" {
  name = "s3-repl-${random_string.random_suffix.result}"
  role = aws_iam_role.CreateBucketReplication.id

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
          "s3:GetObjectVersionTagging"
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
        Resource = "${aws_s3_bucket.CreateBucketReplica.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = aws_kms_key.CreateBucket.arn
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Encrypt",
          "kms:GenerateDataKey"
        ]
        Resource = aws_kms_key.CreateBucketReplica.arn
      }
    ]
  })
}

resource "aws_s3_bucket_replication_configuration" "CreateBucket" {
  depends_on = [
    aws_s3_bucket_versioning.CreateBucket,
    aws_s3_bucket_versioning.CreateBucketReplica,
    aws_iam_role_policy.CreateBucketReplication
  ]

  role   = aws_iam_role.CreateBucketReplication.arn
  bucket = aws_s3_bucket.CreateBucket.id

  rule {
    id       = "replicate-all"
    status   = "Enabled"
    priority = 0

    filter {}

    delete_marker_replication {
      status = "Enabled"
    }

    source_selection_criteria {
      sse_kms_encrypted_objects {
        status = "Enabled"
      }
    }

    destination {
      bucket        = aws_s3_bucket.CreateBucketReplica.arn
      storage_class = "STANDARD"

      encryption_configuration {
        replica_kms_key_id = aws_kms_key.CreateBucketReplica.arn
      }
    }
  }
}

resource "aws_sns_topic" "CreateBucket" {
  name = "s3-notify-${random_string.random_suffix.result}"
}

resource "aws_sns_topic_policy" "CreateBucket" {
  arn = aws_sns_topic.CreateBucket.arn
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "s3.amazonaws.com"
        }
        Action   = "SNS:Publish"
        Resource = aws_sns_topic.CreateBucket.arn
        Condition = {
          ArnLike = {
            "aws:SourceArn" = aws_s3_bucket.CreateBucket.arn
          }
        }
      }
    ]
  })
}

resource "aws_s3_bucket_notification" "CreateBucket" {
  bucket = aws_s3_bucket.CreateBucket.id

  topic {
    topic_arn = aws_sns_topic.CreateBucket.arn
    events    = ["s3:ObjectCreated:*"]
  }

  depends_on = [aws_sns_topic_policy.CreateBucket]
}

resource "aws_s3_object" "PutObject_Flag" {
  bucket                 = aws_s3_bucket.CreateBucket.id
  key                    = "flag.txt"
  source                 = "./flag.txt"
  acl                    = "private"
  server_side_encryption = "aws:kms"
  kms_key_id             = aws_kms_key.CreateBucket.arn
  depends_on = [
    aws_s3_bucket_acl.CreateBucketAcl,
    aws_s3_bucket_server_side_encryption_configuration.CreateBucket,
    aws_s3_bucket_public_access_block.CreateBucket
  ]
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