data "aws_route53_zone" "this" {
  name = "${replace("${var.site_domain}", "/.*\\b(\\w+\\.\\w+)\\.?$/", "$1")}"
}

resource "random_string" "s3_read_password" {
  length  = 32
  special = false
}

resource "aws_kms_key" "this" {
  count                   = "${var.bucket_override_name == "" ? 1 : 0}"
  description             = "KMS key for S3 bucket encryption"
  deletion_window_in_days = 10
  tags                    = "${var.tags}"
}

module "aws_reverse_proxy" {
  source = "git::ssh://git@github.com/futurice/terraform-utils.git//aws_reverse_proxy?ref=4b29f8dc8c0cf64d633b63f7d2f17f5c47952e1e"

  origin_url = "http://${local.bucket_domain_name}/"

  origin_custom_header_name = "User-Agent"

  origin_custom_header_value = "${random_string.s3_read_password.result}"

  site_domain            = "${var.site_domain}"
  name_prefix            = "${var.name_prefix}"
  comment_prefix         = "${var.comment_prefix}"
  cloudfront_price_class = "${var.cloudfront_price_class}"
  viewer_https_only      = "${var.viewer_https_only}"
  cache_ttl_override     = "${var.cache_ttl_override}"
  default_root_object    = "${var.default_root_object}"
  add_response_headers   = "${var.add_response_headers}"
  basic_auth_username    = "${var.basic_auth_username}"
  basic_auth_password    = "${var.basic_auth_password}"
  basic_auth_realm       = "${var.basic_auth_realm}"
  basic_auth_body        = "${var.basic_auth_body}"
  lambda_logging_enabled = "${var.lambda_logging_enabled}"
  tags                   = "${var.tags}"
}

output "bucket_name" {
  description = "The name of the S3 bucket that's used for hosting the content (either auto-generated or externally provided)"

  value = "${local.bucket_name}${replace("${element(concat(aws_s3_bucket.this.*.bucket, list("")), 0)}", "/.*/", "")}"
}

output "cloudfront_id" {
  description = "The ID of the CloudFront distribution that's used for hosting the content"
  value       = "${module.aws_reverse_proxy.cloudfront_id}"
}

output "site_domain" {
  description = "Domain on which the static site will be made available"
  value       = "${var.site_domain}"
}

output "bucket_domain_name" {
  description = "Full S3 domain name for the bucket used for hosting the content (e.g. `\"aws-static-site---hello-example-com.s3-website.eu-central-1.amazonaws.com\"`)"
  value       = "${local.bucket_domain_name}"
}

data "aws_region" "current" {}

resource "aws_s3_bucket" "this" {
  count  = "${var.bucket_override_name == "" ? 1 : 0}"
  bucket = "${local.bucket_name}"
  tags   = "${var.tags}"

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET"]
    allowed_origins = ["*"]
    max_age_seconds = 3000
  }

  website {
    index_document = "index.html"
    error_document = "error.html"
  }

  versioning {
    enabled = true
  }

  logging {
    target_bucket = "${aws_s3_bucket.logs[0].id}"
    target_prefix = "log/"
  }

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm     = "aws:kms"
        kms_master_key_id = "${aws_kms_key.this[0].arn}"
      }
    }
  }

  lifecycle_rule {
    id      = "default"
    enabled = true

    noncurrent_version_expiration {
      days = 90
    }
  }

  replication_configuration {
    role = "${aws_iam_role.replication[0].arn}"

    rules {
      id     = "replicate-all"
      status = "Enabled"

      destination {
        bucket        = "${aws_s3_bucket.replica[0].arn}"
        storage_class = "STANDARD"
      }
    }
  }
}

resource "aws_s3_bucket_public_access_block" "this" {
  count  = "${var.bucket_override_name == "" ? 1 : 0}"
  bucket = "${aws_s3_bucket.this[0].id}"

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_notification" "this" {
  count  = "${var.bucket_override_name == "" ? 1 : 0}"
  bucket = "${aws_s3_bucket.this[0].id}"
}

resource "aws_s3_bucket" "logs" {
  count  = "${var.bucket_override_name == "" ? 1 : 0}"
  bucket = "${local.bucket_name}-logs"
  tags   = "${var.tags}"

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm     = "aws:kms"
        kms_master_key_id = "${aws_kms_key.this[0].arn}"
      }
    }
  }
}

resource "aws_s3_bucket_public_access_block" "logs" {
  count  = "${var.bucket_override_name == "" ? 1 : 0}"
  bucket = "${aws_s3_bucket.logs[0].id}"

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket" "replica" {
  count    = "${var.bucket_override_name == "" ? 1 : 0}"
  bucket   = "${local.bucket_name}-replica"
  tags     = "${var.tags}"
  provider = "aws.replica"

  versioning {
    enabled = true
  }

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  }
}

resource "aws_iam_role" "replication" {
  count = "${var.bucket_override_name == "" ? 1 : 0}"
  name  = "${local.bucket_name}-replication-role"

  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "s3.amazonaws.com"
      },
      "Effect": "Allow"
    }
  ]
}
POLICY
}

resource "aws_iam_policy" "replication" {
  count = "${var.bucket_override_name == "" ? 1 : 0}"
  name  = "${local.bucket_name}-replication-policy"

  policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "s3:GetReplicationConfiguration",
        "s3:ListBucket"
      ],
      "Effect": "Allow",
      "Resource": [
        "${aws_s3_bucket.this[0].arn}"
      ]
    },
    {
      "Action": [
        "s3:GetObjectVersionForReplication",
        "s3:GetObjectVersionAcl"
      ],
      "Effect": "Allow",
      "Resource": [
        "${aws_s3_bucket.this[0].arn}/*"
      ]
    },
    {
      "Action": [
        "s3:ReplicateObject",
        "s3:ReplicateDelete"
      ],
      "Effect": "Allow",
      "Resource": "${aws_s3_bucket.replica[0].arn}/*"
    }
  ]
}
POLICY
}

resource "aws_iam_role_policy_attachment" "replication" {
  count      = "${var.bucket_override_name == "" ? 1 : 0}"
  role       = "${aws_iam_role.replication[0].name}"
  policy_arn = "${aws_iam_policy.replication[0].arn}"
}

resource "aws_s3_bucket_policy" "this" {
  depends_on = ["aws_s3_bucket.this"]
  count      = "${var.bucket_override_name == "" ? 1 : 0}"
  bucket     = "${local.bucket_name}"

  policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "${aws_iam_role.cloudfront_access[0].arn}"
      },
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::${local.bucket_name}/*",
      "Condition": {
        "StringEquals": {
          "aws:UserAgent": "${random_string.s3_read_password.result}"
        }
      }
    }
  ]
}
POLICY
}

resource "aws_iam_role" "cloudfront_access" {
  count = "${var.bucket_override_name == "" ? 1 : 0}"
  name  = "${local.bucket_name}-cloudfront-access"

  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "cloudfront.amazonaws.com"
      },
      "Effect": "Allow"
    }
  ]
}
POLICY
}

variable "site_domain" {
  description = "Domain on which the static site will be made available (e.g. `\"www.example.com\"`)"
}

variable "name_prefix" {
  description = "Name prefix to use for objects that need to be created (only lowercase alphanumeric characters and hyphens allowed, for S3 bucket name compatibility)"
  default     = "aws-static-site---"
}

variable "comment_prefix" {
  description = "This will be included in comments for resources that are created"
  default     = "Static site: "
}

variable "bucket_override_name" {
  description = "When provided, assume a bucket with this name already exists for the site content, instead of creating the bucket automatically (e.g. `\"my-bucket\"`)"
  default     = ""
}

variable "cloudfront_price_class" {
  description = "CloudFront price class to use (`100`, `200` or `\"All\"`, see https://aws.amazon.com/cloudfront/pricing/)"
  default     = 100
}

variable "viewer_https_only" {
  description = "Set this to `false` if you need to support insecure HTTP access for clients, in addition to HTTPS"
  default     = true
}

variable "cache_ttl_override" {
  description = "When >= 0, override the cache behaviour for ALL objects in S3, so that they stay in the CloudFront cache for this amount of seconds"
  default     = -1
}

variable "default_root_object" {
  description = "The object to return when the root URL is requested"
  default     = "index.html"
}

variable "add_response_headers" {
  description = "Map of HTTP headers (if any) to add to outgoing responses before sending them to clients"
  type        = "map"

  default = {
    "Strict-Transport-Security" = "max-age=31557600; preload"
  }
}

variable "basic_auth_username" {
  description = "When non-empty, require this username with HTTP Basic Auth"
  default     = ""
}

variable "basic_auth_password" {
  description = "When non-empty, require this password with HTTP Basic Auth"
  default     = ""
}

variable "basic_auth_realm" {
  description = "When using HTTP Basic Auth, this will be displayed by the browser in the auth prompt"
  default     = "Authentication Required"
}

variable "basic_auth_body" {
  description = "When using HTTP Basic Auth, and authentication has failed, this will be displayed by the browser as the page content"
  default     = "Unauthorized"
}

variable "lambda_logging_enabled" {
  description = "When true, writes information about incoming requests to the Lambda function's CloudWatch group"
  default     = false
}

variable "tags" {
  description = "AWS Tags to add to all resources created (where possible); see https://aws.amazon.com/answers/account-management/aws-tagging-strategies/"
  type        = "map"
  default     = {}
}

locals {
  prefix_with_domain = "${var.name_prefix}${replace("${var.site_domain}", "/[^a-z0-9-]+/", "-")}"
  bucket_name        = "${var.bucket_override_name == "" ? "${local.prefix_with_domain}" : "${var.bucket_override_name}"}"
  bucket_domain_name = "${local.bucket_name}.s3-website.${data.aws_region.current.name}.amazonaws.com"
  error_ttl          = "${var.cache_ttl_override >= 0 ? var.cache_ttl_override : 0}"
}

provider "aws" {
  alias  = "replica"
  region = "us-west-2"
}