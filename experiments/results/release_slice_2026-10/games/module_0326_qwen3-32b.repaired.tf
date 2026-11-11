data "aws_caller_identity" "current" {}

resource "aws_cloudtrail" "main" {
  count = var.not_configured ? 0 : 1
  depends_on = [aws_s3_bucket_policy.CloudTrailS3Bucket-Policy]

  name = var.name
  s3_bucket_name = var.no_logging ? null : aws_s3_bucket.logging[0].bucket
  cloud_watch_logs_role_arn = aws_iam_role.cloudtrail_cwl.arn
  cloud_watch_logs_trail = true
  is_multi_region_trail = true
  kms_key_id = aws_kms_key.cloudtrail_kms.arn

  include_global_service_events = (var.duplicated_global_services_logging || !var.no_global_services_logging)
  enable_logging = !var.no_logging
  enable_log_file_validation = !var.no_log_file_validation
  event_selectors = var.no_data_logging == true ? [] : [
    {
      read_write_type           = "All"
      include_management_events = true
      data_resource {
        type   = "AWS::S3::Object"
        values = ["arn:aws:s3:::"]
      }
    }
  ]
}

resource "aws_s3_bucket" "logging" {
  bucket_prefix = var.name
  force_destroy = true
  count = var.no_logging ? 0 : 1
  versioning {
    enabled = true
  }
  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "aws:kms"
        kms_master_key_id = aws_kms_key.s3_kms.arn
      }
    }
  }
  logging {
    target_bucket = self.id
    target_prefix = "log/"
  }
  public_access_block {
    block_public_acls    = true
    block_public_policy  = true
    ignore_public_acls   = true
    restrict_public_buckets = true
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
  cloud_watch_logs_role_arn = aws_iam_role.cloudtrail_cwl.arn
  cloud_watch_logs_trail = true
  is_multi_region_trail = true
  kms_key_id = aws_kms_key.cloudtrail_kms.arn
  count = (var.duplicated_global_services_logging && !var.no_data_logging) ? 1 : 0
}

resource "aws_kms_key" "cloudtrail_kms" {
  description = "KMS key for CloudTrail encryption"
  policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "Enable CloudTrail access",
      "Effect": "Allow",
      "Principal": {
        "Service": "cloudtrail.amazonaws.com"
      },
      "Action": "kms:*",
      "Resource": "*"
    }
  ]
}
POLICY
}

resource "aws_kms_key" "s3_kms" {
  description = "KMS key for S3 encryption"
  policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "Enable S3 access",
      "Effect": "Allow",
      "Principal": {
        "Service": "s3.amazonaws.com"
      },
      "Action": "kms:*",
      "Resource": "*"
    }
  ]
}
POLICY
}

resource "aws_iam_role" "cloudtrail_cwl" {
  name = "cloudtrail_cwl_role"
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