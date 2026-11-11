data "aws_caller_identity" "current" {}

resource "aws_kms_key" "cloudtrail" {
  count = var.not_configured ? 0 : 1
  description             = "KMS key for CloudTrail encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "Enable IAM User Permissions",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
      },
      "Action": "kms:*",
      "Resource": "*"
    },
    {
      "Sid": "Allow CloudTrail to encrypt logs",
      "Effect": "Allow",
      "Principal": {
        "Service": "cloudtrail.amazonaws.com"
      },
      "Action": [
        "kms:GenerateDataKey*",
        "kms:DescribeKey"
      ],
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "kms:CallerAccount": "${data.aws_caller_identity.current.account_id}",
          "kms:ViaService": "cloudtrail.${var.region}.amazonaws.com"
        }
      }
    },
    {
      "Sid": "Allow CloudTrail to describe key",
      "Effect": "Allow",
      "Principal": {
        "Service": "cloudtrail.amazonaws.com"
      },
      "Action": "kms:DescribeKey",
      "Resource": "*"
    }
  ]
}
POLICY
}

resource "aws_kms_key" "s3" {
  count = var.no_logging ? 0 : 1
  description             = "KMS key for S3 bucket encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "Enable IAM User Permissions",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
      },
      "Action": "kms:*",
      "Resource": "*"
    },
    {
      "Sid": "Allow CloudTrail to encrypt logs",
      "Effect": "Allow",
      "Principal": {
        "Service": "cloudtrail.amazonaws.com"
      },
      "Action": [
        "kms:GenerateDataKey*",
        "kms:DescribeKey"
      ],
      "Resource": "*"
    },
    {
      "Sid": "Allow S3 service to use key",
      "Effect": "Allow",
      "Principal": {
        "Service": "s3.amazonaws.com"
      },
      "Action": [
        "kms:GenerateDataKey*",
        "kms:DescribeKey"
      ],
      "Resource": "*"
    }
  ]
}
POLICY
}

resource "aws_sns_topic" "cloudtrail" {
  count = var.not_configured ? 0 : 1
  name  = "${var.name}-cloudtrail-notifications"
}

resource "aws_cloudwatch_log_group" "cloudtrail" {
  count = var.not_configured ? 0 : 1
  name  = "${var.name}-cloudtrail-logs"
  kms_key_id = aws_kms_key.cloudtrail[0].arn
}

resource "aws_iam_role" "cloudtrail_cloudwatch" {
  count = var.not_configured ? 0 : 1
  name  = "${var.name}-cloudtrail-cloudwatch-role"

  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "cloudtrail.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
POLICY
}

resource "aws_iam_role_policy" "cloudtrail_cloudwatch" {
  count = var.not_configured ? 0 : 1
  name  = "${var.name}-cloudtrail-cloudwatch-policy"
  role  = aws_iam_role.cloudtrail_cloudwatch[0].id

  policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "${aws_cloudwatch_log_group.cloudtrail[0].arn}:*"
    }
  ]
}
POLICY
}

resource "aws_cloudtrail" "main" {
  count = var.not_configured ? 0 : 1
  depends_on = [aws_s3_bucket_policy.CloudTrailS3Bucket-Policy]

  name = var.name
  s3_bucket_name = var.no_logging ? null : aws_s3_bucket.logging[0].bucket

  include_global_service_events = (var.duplicated_global_services_logging || !var.no_global_services_logging)
  enable_logging = !var.no_logging
  enable_log_file_validation = !var.no_log_file_validation
  is_multi_region_trail = true
  kms_key_id = aws_kms_key.cloudtrail[0].arn
  sns_topic_name = aws_sns_topic.cloudtrail[0].name
  cloud_watch_logs_group_arn = aws_cloudwatch_log_group.cloudtrail[0].arn
  cloud_watch_logs_role_arn = aws_iam_role.cloudtrail_cloudwatch[0].arn

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
  count = var.no_logging ? 0 : 1
  bucket = aws_s3_bucket.logging[0].id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "logging" {
  count = var.no_logging ? 0 : 1
  bucket = aws_s3_bucket.logging[0].id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.s3[0].arn
      sse_algorithm     = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "logging" {
  count = var.no_logging ? 0 : 1
  bucket = aws_s3_bucket.logging[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_logging" "logging" {
  count = var.no_logging ? 0 : 1
  bucket = aws_s3_bucket.logging[0].id

  target_bucket = aws_s3_bucket.logging[0].id
  target_prefix = "access-logs/"
}

resource "aws_s3_bucket_lifecycle_configuration" "logging" {
  count = var.no_logging ? 0 : 1
  bucket = aws_s3_bucket.logging[0].id

  rule {
    id     = "transition-to-glacier"
    status = "Enabled"

    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    expiration {
      days = 365
    }
  }
}

resource "aws_s3_bucket_notification" "logging" {
  count = var.no_logging ? 0 : 1
  bucket = aws_s3_bucket.logging[0].id

  topic {
    topic_arn     = aws_sns_topic.cloudtrail[0].arn
    events        = ["s3:ObjectCreated:*"]
    filter_suffix = ".log"
  }
}

resource "aws_s3_bucket_policy" "CloudTrailS3Bucket-Policy" {
  bucket = aws_s3_bucket.logging[0].id
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

resource "aws_cloudtrail" "duplicate" {
  depends_on = [aws_s3_bucket_policy.CloudTrailS3Bucket-Policy]
  name = "duplicatesadcloud"
  include_global_service_events = true
  s3_bucket_name = aws_s3_bucket.logging[0].bucket
  is_multi_region_trail = true
  enable_log_file_validation = true
  enable_logging = true
  kms_key_id = aws_kms_key.cloudtrail[0].arn
  cloud_watch_logs_group_arn = aws_cloudwatch_log_group.cloudtrail[0].arn
  cloud_watch_logs_role_arn = aws_iam_role.cloudtrail_cloudwatch[0].arn

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

variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}