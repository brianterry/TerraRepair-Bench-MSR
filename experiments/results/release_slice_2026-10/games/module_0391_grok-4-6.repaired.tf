provider "aws" {
  region = "us-east-1"
}

provider "aws" {
  alias  = "replica"
  region = "us-west-2"
}

resource "aws_kms_key" "huoxian" {
  description             = "CMK for huoxian S3 bucket"
  deletion_window_in_days = 10
  enable_key_rotation     = true
}

resource "aws_kms_key" "huoxian_replica" {
  provider                = aws.replica
  description             = "CMK for huoxian S3 replica bucket"
  deletion_window_in_days = 10
  enable_key_rotation     = true
}

resource "aws_s3_bucket" "huoxian_bucket" {
  force_destroy = true
  bucket        = "houxian${random_string.random_suffix.result}"
}

resource "aws_s3_bucket" "huoxian_bucket_logs" {
  force_destroy = true
  bucket        = "houxian${random_string.random_suffix.result}-logs"
}

resource "aws_s3_bucket" "huoxian_bucket_replica" {
  provider      = aws.replica
  force_destroy = true
  bucket        = "houxian${random_string.random_suffix.result}-replica"
}

resource "aws_s3_bucket_ownership_controls" "huoxian_bucket" {
  bucket = aws_s3_bucket.huoxian_bucket.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_public_access_block" "huoxian_bucket" {
  bucket                  = aws_s3_bucket.huoxian_bucket.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "huoxian_bucket_logs" {
  bucket                  = aws_s3_bucket.huoxian_bucket_logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "huoxian_bucket_replica" {
  provider                = aws.replica
  bucket                  = aws_s3_bucket.huoxian_bucket_replica.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_acl" "huoxian_bucket_acl" {
  bucket = aws_s3_bucket.huoxian_bucket.id
  depends_on = [
    aws_s3_bucket.huoxian_bucket,
    aws_s3_bucket_ownership_controls.huoxian_bucket,
    aws_s3_bucket_public_access_block.huoxian_bucket,
  ]
  access_control_policy {
    grant {
      grantee {
        type = "CanonicalUser"
        id   = data.aws_canonical_user_id.current.id
      }
      permission = "FULL_CONTROL"
    }
    owner {
      id = data.aws_canonical_user_id.current.id
    }
  }
}

resource "aws_s3_bucket_versioning" "huoxian_bucket" {
  bucket = aws_s3_bucket.huoxian_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_versioning" "huoxian_bucket_replica" {
  provider = aws.replica
  bucket   = aws_s3_bucket.huoxian_bucket_replica.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "huoxian_bucket" {
  bucket = aws_s3_bucket.huoxian_bucket.id
  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.huoxian.arn
      sse_algorithm     = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "huoxian_bucket_logs" {
  bucket = aws_s3_bucket.huoxian_bucket_logs.id
  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.huoxian.arn
      sse_algorithm     = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "huoxian_bucket_replica" {
  provider = aws.replica
  bucket   = aws_s3_bucket.huoxian_bucket_replica.id
  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.huoxian_replica.arn
      sse_algorithm     = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_policy" "huoxian_bucket_logs" {
  bucket = aws_s3_bucket.huoxian_bucket_logs.id
  depends_on = [
    aws_s3_bucket_public_access_block.huoxian_bucket_logs,
  ]
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
        Resource = "${aws_s3_bucket.huoxian_bucket_logs.arn}/log/*"
        Condition = {
          ArnLike = {
            "aws:SourceArn" = aws_s3_bucket.huoxian_bucket.arn
          }
        }
      }
    ]
  })
}

resource "aws_s3_bucket_logging" "huoxian_bucket" {
  bucket        = aws_s3_bucket.huoxian_bucket.id
  target_bucket = aws_s3_bucket.huoxian_bucket_logs.id
  target_prefix = "log/"
  depends_on = [
    aws_s3_bucket_policy.huoxian_bucket_logs,
  ]
}

resource "aws_s3_bucket_lifecycle_configuration" "huoxian_bucket" {
  bucket = aws_s3_bucket.huoxian_bucket.id
  depends_on = [
    aws_s3_bucket_versioning.huoxian_bucket,
  ]
  rule {
    id     = "default-lifecycle"
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

resource "aws_s3_bucket_notification" "huoxian_bucket" {
  bucket      = aws_s3_bucket.huoxian_bucket.id
  eventbridge = true
}

resource "aws_iam_role" "huoxian_replication" {
  name = "huoxian-replication-${random_string.random_suffix.result}"
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

resource "aws_iam_role_policy" "huoxian_replication" {
  name = "huoxian-replication-${random_string.random_suffix.result}"
  role = aws_iam_role.huoxian_replication.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetReplicationConfiguration",
          "s3:ListBucket"
        ]
        Resource = [aws_s3_bucket.huoxian_bucket.arn]
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
        Resource = ["${aws_s3_bucket.huoxian_bucket.arn}/*"]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ReplicateObject",
          "s3:ReplicateDelete",
          "s3:ReplicateTags"
        ]
        Resource = ["${aws_s3_bucket.huoxian_bucket_replica.arn}/*"]
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = [aws_kms_key.huoxian.arn]
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Encrypt",
          "kms:GenerateDataKey"
        ]
        Resource = [aws_kms_key.huoxian_replica.arn]
      }
    ]
  })
}

resource "aws_s3_bucket_replication_configuration" "huoxian_bucket" {
  bucket = aws_s3_bucket.huoxian_bucket.id
  role   = aws_iam_role.huoxian_replication.arn
  depends_on = [
    aws_s3_bucket_versioning.huoxian_bucket,
    aws_s3_bucket_versioning.huoxian_bucket_replica,
  ]
  rule {
    id     = "replicate-all"
    status = "Enabled"
    filter {
      prefix = ""
    }
    delete_marker_replication {
      status = "Disabled"
    }
    source_selection_criteria {
      sse_kms_encrypted_objects {
        status = "Enabled"
      }
    }
    destination {
      bucket        = aws_s3_bucket.huoxian_bucket_replica.arn
      storage_class = "STANDARD"
      encryption_configuration {
        replica_kms_key_id = aws_kms_key.huoxian_replica.arn
      }
    }
  }
}

resource "aws_s3_object" "huoxian_object" {
  bucket                 = aws_s3_bucket.huoxian_bucket.id
  acl                    = "private"
  key                    = "flag1650859"
  source                 = "./flag1650859"
  server_side_encryption = "aws:kms"
  kms_key_id             = aws_kms_key.huoxian.arn
  depends_on = [
    aws_s3_bucket.huoxian_bucket,
    aws_s3_bucket_public_access_block.huoxian_bucket,
    aws_s3_bucket_server_side_encryption_configuration.huoxian_bucket,
    aws_s3_bucket_acl.huoxian_bucket_acl,
  ]
}

resource "random_string" "random_suffix" {
  length  = 5
  special = false
  upper   = false
}

data "aws_canonical_user_id" "current" {}

output "aws_s3_bucket_name" {
  value       = "https://${aws_s3_bucket.huoxian_bucket.bucket}.s3.us-east-1.amazonaws.com"
  description = "This is the bucket name of AWS S3 Service."
}

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "4.10.0"
    }
  }
}