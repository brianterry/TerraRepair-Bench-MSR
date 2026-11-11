resource "aws_s3_bucket" "logs" {
  bucket        = var.audit_s3_bucket_name
  force_destroy = true
}

resource "aws_s3_bucket_ownership_controls" "logs" {
  bucket = aws_s3_bucket.logs.id

  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_acl" "logs" {
  depends_on = [aws_s3_bucket_ownership_controls.logs]
  bucket     = aws_s3_bucket.logs.id
  acl        = "private"
}

resource "aws_s3_bucket_public_access_block" "logs" {
  bucket = aws_s3_bucket.logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "logs" {
  bucket = aws_s3_bucket.logs.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_kms_key" "logs" {
  description             = "CMK for audit logs S3 bucket"
  deletion_window_in_days = 10
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow CloudTrail and Config to use the key"
        Effect = "Allow"
        Principal = {
          Service = [
            "cloudtrail.amazonaws.com",
            "config.amazonaws.com"
          ]
        }
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey*"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_s3_bucket_server_side_encryption_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.logs.arn
      sse_algorithm     = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_logging" "logs" {
  bucket = aws_s3_bucket.logs.id

  target_bucket = aws_s3_bucket.logs.id
  target_prefix = "s3-access-logs/"
}

resource "aws_s3_bucket_lifecycle_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id

  rule {
    id     = "audit-log-lifecycle"
    status = "Enabled"

    filter {
      prefix = ""
    }

    transition {
      days          = 90
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 180
      storage_class = "GLACIER"
    }

    noncurrent_version_transition {
      noncurrent_days = 30
      storage_class   = "GLACIER"
    }
  }
}

resource "aws_sns_topic" "logs" {
  name              = "${var.audit_s3_bucket_name}-notifications"
  kms_master_key_id = aws_kms_key.logs.id
}

resource "aws_sns_topic_policy" "logs" {
  arn = aws_sns_topic.logs.arn

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
        Resource = aws_sns_topic.logs.arn
        Condition = {
          ArnLike = {
            "aws:SourceArn" = aws_s3_bucket.logs.arn
          }
        }
      }
    ]
  })
}

resource "aws_s3_bucket_notification" "logs" {
  bucket = aws_s3_bucket.logs.id

  topic {
    topic_arn = aws_sns_topic.logs.arn
    events    = ["s3:ObjectCreated:*"]
  }

  depends_on = [aws_sns_topic_policy.logs]
}

resource "aws_kms_key" "logs_replica" {
  provider                = aws.us-west-2
  description             = "CMK for audit logs S3 replica bucket"
  deletion_window_in_days = 10
  enable_key_rotation     = true
}

resource "aws_s3_bucket" "logs_replica" {
  provider      = aws.us-west-2
  bucket        = "${var.audit_s3_bucket_name}-replica"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "logs_replica" {
  provider = aws.us-west-2
  bucket   = aws_s3_bucket.logs_replica.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "logs_replica" {
  provider = aws.us-west-2
  bucket   = aws_s3_bucket.logs_replica.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "logs_replica" {
  provider = aws.us-west-2
  bucket   = aws_s3_bucket.logs_replica.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.logs_replica.arn
      sse_algorithm     = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_iam_role" "replication" {
  name = "${var.audit_s3_bucket_name}-replication"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "s3.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "replication" {
  name = "${var.audit_s3_bucket_name}-replication"
  role = aws_iam_role.replication.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "s3:GetReplicationConfiguration",
          "s3:ListBucket"
        ]
        Effect   = "Allow"
        Resource = aws_s3_bucket.logs.arn
      },
      {
        Action = [
          "s3:GetObjectVersionForReplication",
          "s3:GetObjectVersionAcl",
          "s3:GetObjectVersionTagging"
        ]
        Effect   = "Allow"
        Resource = "${aws_s3_bucket.logs.arn}/*"
      },
      {
        Action = [
          "s3:ReplicateObject",
          "s3:ReplicateDelete",
          "s3:ReplicateTags"
        ]
        Effect   = "Allow"
        Resource = "${aws_s3_bucket.logs_replica.arn}/*"
      },
      {
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Effect   = "Allow"
        Resource = aws_kms_key.logs.arn
      },
      {
        Action = [
          "kms:Encrypt",
          "kms:GenerateDataKey"
        ]
        Effect   = "Allow"
        Resource = aws_kms_key.logs_replica.arn
      }
    ]
  })
}

resource "aws_s3_bucket_replication_configuration" "logs" {
  depends_on = [
    aws_s3_bucket_versioning.logs,
    aws_s3_bucket_versioning.logs_replica
  ]

  role   = aws_iam_role.replication.arn
  bucket = aws_s3_bucket.logs.id

  rule {
    id     = "replicate-everything"
    status = "Enabled"

    filter {
      prefix = ""
    }

    delete_marker_replication {
      status = "Enabled"
    }

    source_selection_criteria {
      sse_kms_encrypted_objects {
        status = "Enabled"
      }
    }

    destination {
      bucket        = aws_s3_bucket.logs_replica.arn
      storage_class = "STANDARD"

      encryption_configuration {
        replica_kms_key_id = aws_kms_key.logs_replica.arn
      }
    }
  }
}

data "aws_iam_policy_document" "logs_bucket_policy" {
  statement {
    sid     = "AWSCloudTrailAclCheckForConfig"
    actions = ["s3:GetBucketAcl"]
    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }
    resources = [aws_s3_bucket.logs.arn]
  }

  statement {
    sid     = "AWSCloudTrailWriteForConfig"
    actions = ["s3:PutObject"]
    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }
    resources = ["${aws_s3_bucket.logs.arn}/config/AWSLogs/${data.aws_caller_identity.current.account_id}/Config/*"]
    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
  }

  statement {
    sid     = "AWSCloudTrailAclCheckForCloudTrail"
    actions = ["s3:GetBucketAcl"]
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    resources = [aws_s3_bucket.logs.arn]
  }

  statement {
    sid     = "AWSCloudTrailWriteForCloudTrail"
    actions = ["s3:PutObject"]
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    resources = ["${aws_s3_bucket.logs.arn}/cloudtrail/AWSLogs/*"]
    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
  }
}

resource "aws_s3_bucket_policy" "logs" {
  depends_on = [aws_s3_bucket_public_access_block.logs]
  bucket     = aws_s3_bucket.logs.id
  policy     = data.aws_iam_policy_document.logs_bucket_policy.json
}


terraform {
  required_version = ">= 1.1.4"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 4.3"
    }
  }
}

provider "aws" {
  region = var.region
}

data "aws_caller_identity" "current" {
}

module "secure_baseline" {
  source = "../../"

  audit_log_bucket_name           = aws_s3_bucket.logs.id
  use_external_audit_log_bucket   = true
  aws_account_id                  = data.aws_caller_identity.current.account_id
  region                          = var.region
  support_iam_role_principal_arns = [data.aws_caller_identity.current.arn]

  providers = {
    aws                = aws
    aws.ap-northeast-1 = aws.ap-northeast-1
    aws.ap-northeast-2 = aws.ap-northeast-2
    aws.ap-northeast-3 = aws.ap-northeast-3
    aws.ap-south-1     = aws.ap-south-1
    aws.ap-southeast-1 = aws.ap-southeast-1
    aws.ap-southeast-2 = aws.ap-southeast-2
    aws.ca-central-1   = aws.ca-central-1
    aws.eu-central-1   = aws.eu-central-1
    aws.eu-north-1     = aws.eu-north-1
    aws.eu-west-1      = aws.eu-west-1
    aws.eu-west-2      = aws.eu-west-2
    aws.eu-west-3      = aws.eu-west-3
    aws.sa-east-1      = aws.sa-east-1
    aws.us-east-1      = aws.us-east-1
    aws.us-east-2      = aws.us-east-2
    aws.us-west-1      = aws.us-west-1
    aws.us-west-2      = aws.us-west-2
  }
}





# --------------------------------------------------------------------------------------------------
# A list of providers for all AWS regions.
# Reference: https://docs.aws.amazon.com/general/latest/gr/rande.html
# --------------------------------------------------------------------------------------------------

provider "aws" {
  region = "ap-northeast-1"
  alias  = "ap-northeast-1"
}

provider "aws" {
  region = "ap-northeast-2"
  alias  = "ap-northeast-2"
}

provider "aws" {
  region = "ap-northeast-3"
  alias  = "ap-northeast-3"
}

provider "aws" {
  region = "ap-south-1"
  alias  = "ap-south-1"
}

provider "aws" {
  region = "ap-southeast-1"
  alias  = "ap-southeast-1"
}

provider "aws" {
  region = "ap-southeast-2"
  alias  = "ap-southeast-2"
}

provider "aws" {
  region = "ca-central-1"
  alias  = "ca-central-1"
}

provider "aws" {
  region = "eu-central-1"
  alias  = "eu-central-1"
}

provider "aws" {
  region = "eu-north-1"
  alias  = "eu-north-1"
}

provider "aws" {
  region = "eu-west-1"
  alias  = "eu-west-1"
}

provider "aws" {
  region = "eu-west-2"
  alias  = "eu-west-2"
}

provider "aws" {
  region = "eu-west-3"
  alias  = "eu-west-3"
}

provider "aws" {
  region = "sa-east-1"
  alias  = "sa-east-1"
}

provider "aws" {
  region = "us-east-1"
  alias  = "us-east-1"
}

provider "aws" {
  region = "us-east-2"
  alias  = "us-east-2"
}

provider "aws" {
  region = "us-west-1"
  alias  = "us-west-1"
}

provider "aws" {
  region = "us-west-2"
  alias  = "us-west-2"
}



variable "audit_s3_bucket_name" {
  description = "The name of the S3 bucket to store various audit logs."
  type        = string
}

variable "region" {
  description = "The AWS region in which global resources are set up."
  type        = string
  default     = "us-east-1"
}