provider "aws" {
  region = "us-east-1"
}

provider "aws" {
  alias  = "replica"
  region = "us-west-2"
}

resource "aws_kms_key" "CreateBucketKms" {
  description             = "CMK for CreateBucket encryption"
  deletion_window_in_days = 10
  enable_key_rotation     = true
}

resource "aws_kms_key" "CreateBucketReplicaKms" {
  provider                = aws.replica
  description             = "CMK for replica bucket encryption"
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

resource "aws_s3_bucket" "CreateBucketLogs" {
  force_destroy = true
  bucket        = "hxseclab${random_string.random_suffix.result}-logs"
}

resource "aws_s3_bucket" "CreateBucketReplica" {
  provider      = aws.replica
  force_destroy = true
  bucket        = "hxseclab${random_string.random_suffix.result}-replica"
}

resource "aws_s3_bucket_ownership_controls" "CreateBucketOwnership" {
  bucket = aws_s3_bucket.CreateBucket.id

  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_acl" "CreateBucketAcl" {
  depends_on = [aws_s3_bucket_ownership_controls.CreateBucketOwnership]
  bucket     = aws_s3_bucket.CreateBucket.id
  acl        = "private"
}

resource "aws_s3_bucket_public_access_block" "CreateBucket" {
  bucket                  = aws_s3_bucket.CreateBucket.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "CreateBucketLogs" {
  bucket                  = aws_s3_bucket.CreateBucketLogs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "CreateBucketReplica" {
  provider                = aws.replica
  bucket                  = aws_s3_bucket.CreateBucketReplica.id
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

resource "aws_s3_bucket_versioning" "CreateBucketReplica" {
  provider = aws.replica
  bucket   = aws_s3_bucket.CreateBucketReplica.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_logging" "CreateBucket" {
  bucket        = aws_s3_bucket.CreateBucket.id
  target_bucket = aws_s3_bucket.CreateBucketLogs.id
  target_prefix = "log/"
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
        Resource = "${aws_s3_bucket.CreateBucketLogs.arn}/*"
        Condition = {
          ArnLike = {
            "aws:SourceArn" = aws_s3_bucket.CreateBucket.arn
          }
        }
      }
    ]
  })
}

resource "aws_s3_bucket_server_side_encryption_configuration" "CreateBucket" {
  bucket = aws_s3_bucket.CreateBucket.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.CreateBucketKms.arn
      sse_algorithm     = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "CreateBucketReplica" {
  provider = aws.replica
  bucket   = aws_s3_bucket.CreateBucketReplica.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.CreateBucketReplicaKms.arn
      sse_algorithm     = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "CreateBucket" {
  bucket = aws_s3_bucket.CreateBucket.id

  rule {
    id     = "default-lifecycle"
    status = "Enabled"

    filter {}

    expiration {
      days = 365
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
    Id      = "HuoXian"
    Statement = [
      {
        Sid       = "DenyInsecureTransport"
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

resource "aws_sns_topic" "CreateBucketNotifications" {
  name = "hxseclab${random_string.random_suffix.result}-events"
}

resource "aws_sns_topic_policy" "CreateBucketNotifications" {
  arn = aws_sns_topic.CreateBucketNotifications.arn
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowS3Publish"
        Effect = "Allow"
        Principal = {
          Service = "s3.amazonaws.com"
        }
        Action   = "SNS:Publish"
        Resource = aws_sns_topic.CreateBucketNotifications.arn
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
    topic_arn = aws_sns_topic.CreateBucketNotifications.arn
    events    = ["s3:ObjectCreated:*"]
  }

  depends_on = [aws_sns_topic_policy.CreateBucketNotifications]
}

resource "aws_iam_role" "CreateBucketReplication" {
  name = "hxseclab${random_string.random_suffix.result}-repl"

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
  name = "hxseclab${random_string.random_suffix.result}-repl"
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
        Resource = aws_kms_key.CreateBucketKms.arn
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Encrypt",
          "kms:GenerateDataKey"
        ]
        Resource = aws_kms_key.CreateBucketReplicaKms.arn
      }
    ]
  })
}

resource "aws_s3_bucket_replication_configuration" "CreateBucket" {
  depends_on = [
    aws_s3_bucket_versioning.CreateBucket,
    aws_s3_bucket_versioning.CreateBucketReplica
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
        replica_kms_key_id = aws_kms_key.CreateBucketReplicaKms.arn
      }
    }
  }
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