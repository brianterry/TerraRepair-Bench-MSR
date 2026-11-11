data "aws_caller_identity" "current" {}

resource "aws_kms_key" "cloudtrail" {
  description             = "CMK for CloudTrail and S3 encryption"
  deletion_window_in_days = 7
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
        Sid    = "Allow CloudTrail to encrypt logs"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action = [
          "kms:GenerateDataKey*",
          "kms:DescribeKey",
          "kms:Decrypt"
        ]
        Resource = "*"
      },
      {
        Sid    = "Allow AWS services"
        Effect = "Allow"
        Principal = {
          Service = [
            "s3.amazonaws.com",
            "logs.amazonaws.com",
            "sns.amazonaws.com"
          ]
        }
        Action = [
          "kms:Decrypt",
          "kms:Encrypt",
          "kms:GenerateDataKey*",
          "kms:DescribeKey",
          "kms:CreateGrant",
          "kms:ReEncrypt*"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_cloudwatch_log_group" "cloudtrail" {
  name              = "/aws/cloudtrail/${var.name}"
  retention_in_days = 365
}

resource "aws_iam_role" "cloudtrail_logs" {
  name_prefix = "${var.name}-ct-cw-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "cloudtrail_logs" {
  name_prefix = "${var.name}-ct-cw-"
  role        = aws_iam_role.cloudtrail_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "${aws_cloudwatch_log_group.cloudtrail.arn}:*"
      }
    ]
  })
}

resource "aws_sns_topic" "cloudtrail" {
  name              = "${var.name}-cloudtrail"
  kms_master_key_id = aws_kms_key.cloudtrail.id
}

resource "aws_sns_topic_policy" "cloudtrail" {
  arn = aws_sns_topic.cloudtrail.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSCloudTrailSNSPolicy"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "SNS:Publish"
        Resource = aws_sns_topic.cloudtrail.arn
      },
      {
        Sid    = "AllowS3Notification"
        Effect = "Allow"
        Principal = {
          Service = "s3.amazonaws.com"
        }
        Action   = "SNS:Publish"
        Resource = aws_sns_topic.cloudtrail.arn
      }
    ]
  })
}

resource "aws_cloudtrail" "main" {
  count      = var.not_configured ? 0 : 1
  depends_on = [aws_s3_bucket_policy.CloudTrailS3Bucket-Policy, aws_iam_role_policy.cloudtrail_logs]

  name           = var.name
  s3_bucket_name = var.no_logging ? null : aws_s3_bucket.logging[0].bucket

  include_global_service_events = true
  is_multi_region_trail         = true
  enable_logging                = true
  enable_log_file_validation    = true

  kms_key_id                 = aws_kms_key.cloudtrail.arn
  sns_topic_name             = aws_sns_topic.cloudtrail.name
  cloud_watch_logs_group_arn = "${aws_cloudwatch_log_group.cloudtrail.arn}:*"
  cloud_watch_logs_role_arn  = aws_iam_role.cloudtrail_logs.arn

  dynamic "event_selector" {
    for_each = var.no_data_logging == true ? [] : tolist([var.no_data_logging])

    content {
      read_write_type           = "All"
      include_management_events = true

      data_resource {
        type   = "AWS::S3::Object"
        values = ["arn:aws:s3:::"]
      }
    }
  }
}

resource "aws_s3_bucket" "logging" {
  bucket_prefix = var.name
  force_destroy = true

  count = var.no_logging ? 0 : 1
}

resource "aws_s3_bucket_public_access_block" "logging" {
  count  = var.no_logging ? 0 : 1
  bucket = aws_s3_bucket.logging[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "logging" {
  count  = var.no_logging ? 0 : 1
  bucket = aws_s3_bucket.logging[0].id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "logging" {
  count  = var.no_logging ? 0 : 1
  bucket = aws_s3_bucket.logging[0].id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.cloudtrail.arn
      sse_algorithm     = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_logging" "logging" {
  count         = var.no_logging ? 0 : 1
  bucket        = aws_s3_bucket.logging[0].id
  target_bucket = aws_s3_bucket.logging[0].id
  target_prefix = "s3-access-logs/"
}

resource "aws_s3_bucket_lifecycle_configuration" "logging" {
  count  = var.no_logging ? 0 : 1
  bucket = aws_s3_bucket.logging[0].id

  rule {
    id     = "retention"
    status = "Enabled"

    filter {
      prefix = ""
    }

    expiration {
      days = 365
    }

    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }
}

resource "aws_s3_bucket_notification" "logging" {
  count      = var.no_logging ? 0 : 1
  bucket     = aws_s3_bucket.logging[0].id
  depends_on = [aws_sns_topic_policy.cloudtrail]

  topic {
    topic_arn = aws_sns_topic.cloudtrail.arn
    events    = ["s3:ObjectCreated:*"]
  }
}

resource "aws_s3_bucket" "logging_replica" {
  bucket_prefix = "${var.name}-r"
  force_destroy = true

  count = var.no_logging ? 0 : 1
}

resource "aws_s3_bucket_public_access_block" "logging_replica" {
  count  = var.no_logging ? 0 : 1
  bucket = aws_s3_bucket.logging_replica[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "logging_replica" {
  count  = var.no_logging ? 0 : 1
  bucket = aws_s3_bucket.logging_replica[0].id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "logging_replica" {
  count  = var.no_logging ? 0 : 1
  bucket = aws_s3_bucket.logging_replica[0].id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.cloudtrail.arn
      sse_algorithm     = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_iam_role" "replication" {
  count       = var.no_logging ? 0 : 1
  name_prefix = "${var.name}-repl-"

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
  count       = var.no_logging ? 0 : 1
  name_prefix = "${var.name}-repl-"
  role        = aws_iam_role.replication[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetReplicationConfiguration",
          "s3:ListBucket"
        ]
        Resource = aws_s3_bucket.logging[0].arn
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObjectVersionForReplication",
          "s3:GetObjectVersionAcl",
          "s3:GetObjectVersionTagging"
        ]
        Resource = "${aws_s3_bucket.logging[0].arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ReplicateObject",
          "s3:ReplicateDelete",
          "s3:ReplicateTags"
        ]
        Resource = "${aws_s3_bucket.logging_replica[0].arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:Encrypt",
          "kms:GenerateDataKey*",
          "kms:ReEncrypt*"
        ]
        Resource = aws_kms_key.cloudtrail.arn
      }
    ]
  })
}

resource "aws_s3_bucket_replication_configuration" "logging" {
  count      = var.no_logging ? 0 : 1
  depends_on = [aws_s3_bucket_versioning.logging, aws_s3_bucket_versioning.logging_replica]

  role   = aws_iam_role.replication[0].arn
  bucket = aws_s3_bucket.logging[0].id

  rule {
    id       = "replicate-all"
    status   = "Enabled"
    priority = 0

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
      bucket        = aws_s3_bucket.logging_replica[0].arn
      storage_class = "STANDARD"

      encryption_configuration {
        replica_kms_key_id = aws_kms_key.cloudtrail.arn
      }
    }
  }
}

resource "aws_s3_bucket_policy" "CloudTrailS3Bucket-Policy" {
  bucket     = aws_s3_bucket.logging[0].id
  depends_on = [aws_s3_bucket.logging[0], aws_s3_bucket_public_access_block.logging]

  count = var.no_logging ? 0 : 1

  policy = <<POLICY
{
    "Version": "2012-10-17",
    "Statement": [{
            "Sid": "AWSCloudTrailAclCheck",
            "Effect": "Allow",
            "Principal": { "Service": "cloudtrail.amazonaws.com" },
            "Action": "s3:GetBucketAcl",
            "Resource": "${aws_s3_bucket.logging[0].arn}"
        },
        {
            "Sid": "AWSCloudTrailWrite",
            "Effect": "Allow",
            "Principal": { "Service": "cloudtrail.amazonaws.com" },
            "Action": "s3:PutObject",
            "Resource": ["${aws_s3_bucket.logging[0].arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"],
            "Condition": { "StringEquals": { "s3:x-amz-acl": "bucket-owner-full-control" } }
        }]

}
POLICY
}

resource "aws_cloudtrail" "duplicate" {
  depends_on = [aws_s3_bucket_policy.CloudTrailS3Bucket-Policy, aws_iam_role_policy.cloudtrail_logs]
  name                          = "duplicatesadcloud"
  include_global_service_events = true
  is_multi_region_trail         = true
  enable_logging                = true
  enable_log_file_validation    = true
  s3_bucket_name                = aws_s3_bucket.logging[0].bucket
  kms_key_id                    = aws_kms_key.cloudtrail.arn
  sns_topic_name                = aws_sns_topic.cloudtrail.name
  cloud_watch_logs_group_arn    = "${aws_cloudwatch_log_group.cloudtrail.arn}:*"
  cloud_watch_logs_role_arn     = aws_iam_role.cloudtrail_logs.arn

  count = (var.duplicated_global_services_logging && !var.no_data_logging) ? 1 : 0
}

variable "name" {
  description = "cloudtrail name"
  type        = string
  default     = "sadcloud"
}

variable "no_data_logging" {
  description = "disable data logging"
  type        = bool
  default     = false
}

variable "no_global_services_logging" {
  description = "disable global services logging"
  type        = bool
  default     = false
}

variable "no_log_file_validation" {
  description = "disable log file validation"
  type        = bool
  default     = false
}

variable "no_logging" {
  description = "disable logging"
  type        = bool
  default     = false
}

variable "duplicated_global_services_logging" {
  description = "enable global services logging in second trail"
  type        = bool
  default     = false
}

variable "not_configured" {
  description = "disable cloudtrail"
  type        = bool
  default     = false
}