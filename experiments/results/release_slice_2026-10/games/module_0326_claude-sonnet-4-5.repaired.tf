data "aws_caller_identity" "current" {}

resource "aws_kms_key" "cloudtrail" {
  count = var.not_configured ? 0 : 1
  description             = "KMS key for CloudTrail"
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
        Sid    = "Allow CloudTrail to encrypt logs"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "kms:GenerateDataKey*"
        Resource = "*"
        Condition = {
          StringLike = {
            "kms:EncryptionContext:aws:cloudtrail:arn" = "arn:aws:cloudtrail:*:${data.aws_caller_identity.current.account_id}:trail/*"
          }
        }
      },
      {
        Sid    = "Allow CloudTrail to describe key"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "kms:DescribeKey"
        Resource = "*"
      },
      {
        Sid    = "Allow CloudWatch Logs to use the key"
        Effect = "Allow"
        Principal = {
          Service = "logs.amazonaws.com"
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:CreateGrant",
          "kms:DescribeKey"
        ]
        Resource = "*"
        Condition = {
          ArnLike = {
            "kms:EncryptionContext:aws:logs:arn" = "arn:aws:logs:*:${data.aws_caller_identity.current.account_id}:*"
          }
        }
      }
    ]
  })
}

resource "aws_kms_key" "s3" {
  count = var.no_logging ? 0 : 1
  description             = "KMS key for S3"
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
        Sid    = "Allow S3 to use the key"
        Effect = "Allow"
        Principal = {
          Service = "s3.amazonaws.com"
        }
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_sns_topic" "cloudtrail" {
  count = var.not_configured ? 0 : 1
  name  = "${var.name}-cloudtrail-topic"
}

resource "aws_sns_topic_policy" "cloudtrail" {
  count  = var.not_configured ? 0 : 1
  arn    = aws_sns_topic.cloudtrail[0].arn
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
        Resource = aws_sns_topic.cloudtrail[0].arn
      }
    ]
  })
}

resource "aws_cloudwatch_log_group" "cloudtrail" {
  count = var.not_configured ? 0 : 1
  name  = "/aws/cloudtrail/${var.name}"
}

resource "aws_iam_role" "cloudtrail_cloudwatch" {
  count = var.not_configured ? 0 : 1
  name  = "${var.name}-cloudtrail-cloudwatch-role"

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

resource "aws_iam_role_policy" "cloudtrail_cloudwatch" {
  count = var.not_configured ? 0 : 1
  name  = "${var.name}-cloudtrail-cloudwatch-policy"
  role  = aws_iam_role.cloudtrail_cloudwatch[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSCloudTrailCreateLogStream"
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "${aws_cloudwatch_log_group.cloudtrail[0].arn}:*"
      }
    ]
  })
}

resource "aws_cloudtrail" "main" {
  count      = var.not_configured ? 0 : 1
  depends_on = [aws_s3_bucket_policy.CloudTrailS3Bucket-Policy]

  name                          = var.name
  s3_bucket_name                = var.no_logging ? null : aws_s3_bucket.logging[0].bucket
  is_multi_region_trail         = true
  include_global_service_events = (var.duplicated_global_services_logging || !var.no_global_services_logging)
  enable_logging                = true
  enable_log_file_validation    = true
  kms_key_id                    = aws_kms_key.cloudtrail[0].arn
  sns_topic_name                = aws_sns_topic.cloudtrail[0].name
  cloud_watch_logs_group_arn    = "${aws_cloudwatch_log_group.cloudtrail[0].arn}:*"
  cloud_watch_logs_role_arn     = aws_iam_role.cloudtrail_cloudwatch[0].arn

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
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.s3[0].arn
    }
  }
}

resource "aws_s3_bucket_public_access_block" "logging" {
  count  = var.no_logging ? 0 : 1
  bucket = aws_s3_bucket.logging[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_logging" "logging" {
  count  = var.no_logging ? 0 : 1
  bucket = aws_s3_bucket.logging[0].id

  target_bucket = aws_s3_bucket.logging[0].id
  target_prefix = "log/"
}

resource "aws_s3_bucket_lifecycle_configuration" "logging" {
  count  = var.no_logging ? 0 : 1
  bucket = aws_s3_bucket.logging[0].id

  rule {
    id     = "default"
    status = "Enabled"

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }
  }
}

resource "aws_s3_bucket_notification" "logging" {
  count  = var.no_logging ? 0 : 1
  bucket = aws_s3_bucket.logging[0].id
}

resource "aws_s3_bucket_policy" "CloudTrailS3Bucket-Policy" {
  bucket     = aws_s3_bucket.logging[0].id
  depends_on = [aws_s3_bucket.logging[0]]

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

resource "aws_cloudwatch_log_group" "cloudtrail_duplicate" {
  count = (var.duplicated_global_services_logging && !var.no_data_logging) ? 1 : 0
  name  = "/aws/cloudtrail/duplicatesadcloud"
}

resource "aws_iam_role" "cloudtrail_cloudwatch_duplicate" {
  count = (var.duplicated_global_services_logging && !var.no_data_logging) ? 1 : 0
  name  = "duplicatesadcloud-cloudtrail-cloudwatch-role"

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

resource "aws_iam_role_policy" "cloudtrail_cloudwatch_duplicate" {
  count = (var.duplicated_global_services_logging && !var.no_data_logging) ? 1 : 0
  name  = "duplicatesadcloud-cloudtrail-cloudwatch-policy"
  role  = aws_iam_role.cloudtrail_cloudwatch_duplicate[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSCloudTrailCreateLogStream"
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "${aws_cloudwatch_log_group.cloudtrail_duplicate[0].arn}:*"
      }
    ]
  })
}

resource "aws_cloudtrail" "duplicate" {
  depends_on                 = [aws_s3_bucket_policy.CloudTrailS3Bucket-Policy]
  name                       = "duplicatesadcloud"
  include_global_service_events = true
  s3_bucket_name             = aws_s3_bucket.logging[0].bucket
  cloud_watch_logs_group_arn = "${aws_cloudwatch_log_group.cloudtrail_duplicate[0].arn}:*"
  cloud_watch_logs_role_arn  = aws_iam_role.cloudtrail_cloudwatch_duplicate[0].arn

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