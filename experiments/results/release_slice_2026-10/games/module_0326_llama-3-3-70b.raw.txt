data "aws_caller_identity" "current" {}

resource "aws_cloudtrail" "main" {
  count = var.not_configured ? 0 : 1
  depends_on = [aws_s3_bucket_policy.CloudTrailS3Bucket-Policy, aws_kms_key.cloudtrail]

  name = var.name
  s3_bucket_name = var.no_logging ? null : aws_s3_bucket.logging[0].bucket
  kms_key_id = aws_kms_key.cloudtrail.arn

  include_global_service_events = (var.duplicated_global_services_logging || !var.no_global_services_logging)
  enable_logging = !var.no_logging
  enable_log_file_validation = !var.no_log_file_validation
  is_multi_region_trail = true
  is_organization_trail = false

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

resource "aws_cloudwatch_log_group" "cloudtrail" {
  name = "/aws/cloudtrail/${var.name}"
}

resource "aws_cloudwatch_log_stream" "cloudtrail" {
  name           = "cloudtrail"
  log_group_name = aws_cloudwatch_log_group.cloudtrail.name
}

resource "aws_cloudtrail" "duplicate" {
  depends_on = [aws_s3_bucket_policy.CloudTrailS3Bucket-Policy, aws_kms_key.cloudtrail]
  name = "duplicatesadcloud"
  include_global_service_events = true
  s3_bucket_name = aws_s3_bucket.logging[0].bucket
  kms_key_id = aws_kms_key.cloudtrail.arn

  count = (var.duplicated_global_services_logging && !var.no_data_logging) ? 1 : 0
}

resource "aws_s3_bucket" "logging" {
  bucket_prefix = var.name
  force_destroy = true
  versioning {
    enabled = true
  }
  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        kms_master_key_id = aws_kms_key.s3.arn
        sse_algorithm     = "aws:kms"
      }
    }
  }

  count = var.no_logging ? 0 : 1
}

resource "aws_s3_bucket_public_access_block" "logging" {
  bucket = aws_s3_bucket.logging[0].id
  block_public_acls   = true
  block_public_policy = true
  ignore_public_acls  = true
  restrict_public_buckets = true

  count = var.no_logging ? 0 : 1
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
        },
        {
          "Sid": "DenyIncorrectEncryptionHeader",
          "Effect": "Deny",
          "Principal": "*",
          "Action": "s3:PutObject",
          "Resource": "${aws_s3_bucket.logging[0].arn}/*",
          "Condition": {
            "StringNotEquals": {
              "s3:x-amz-server-side-encryption": "aws:kms"
            }
          }
        },
        {
          "Sid": "DenyUnencryptedObjectUploads",
          "Effect": "Deny",
          "Principal": "*",
          "Action": "s3:PutObject",
          "Resource": "${aws_s3_bucket.logging[0].arn}/*",
          "Condition": {
            "Null": {
              "s3:x-amz-server-side-encryption": "true"
            }
          }
        }
    ]
}
POLICY
}

resource "aws_kms_key" "cloudtrail" {
}

resource "aws_kms_key" "s3" {
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