data "aws_route53_zone" "this" {
  name = "${replace("${var.site_domain}", "/.*\\b(\\w+\\.\\w+)\\.?$/", "$1")}"
}

resource "random_string" "s3_read_password" {
  length  = 32
  special = false
}

module "aws_reverse_proxy" {
  source = "git::ssh://git@github.com/futurice/terraform-utils.git//aws_reverse_proxy?ref=abc123"

  origin_url                 = "http://${local.bucket_domain_name}/"
  origin_custom_header_name  = "User-Agent"
  origin_custom_header_value = "${random_string.s3_read_password.result}"
  site_domain                = "${var.site_domain}"
  name_prefix                = "${var.name_prefix}"
  comment_prefix             = "${var.comment_prefix}"
  cloudfront_price_class     = "${var.cloudfront_price_class}"
  viewer_https_only          = "${var.viewer_https_only}"
  cache_ttl_override         = "${var.cache_ttl_override}"
  default_root_object        = "${var.default_root_object}"
  add_response_headers       = "${var.add_response_headers}"
  basic_auth_username        = "${var.basic_auth_username}"
  basic_auth_password        = "${var.basic_auth_password}"
  basic_auth_realm           = "${var.basic_auth_realm}"
  basic_auth_body            = "${var.basic_auth_body}"
  lambda_logging_enabled     = "${var.lambda_logging_enabled}"
  tags                       = "${var.tags}"
}

output "bucket_name" {
  value = "${local.bucket_name}${replace("${element(concat(aws_s3_bucket.this.*.bucket, list("")), 0)}", "/.*/", "")}"
}

output "cloudfront_id" {
  value = "${module.aws_reverse_proxy.cloudfront_id}"
}

output "site_domain" {
  value = "${var.site_domain}"
}

output "bucket_domain_name" {
  value = "${local.bucket_domain_name}"
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
    target_bucket = "${local.bucket_name}"
    target_prefix = "logs/"
  }

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm     = "aws:kms"
        kms_master_key_id = "alias/aws/s3"
      }
    }
  }

  lifecycle_rule {
    enabled = true
    expiration {
      days = 365
    }
  }
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
      "Principal": {"AWS": "*"},
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

resource "aws_s3_bucket_public_access_block" "this" {
  bucket = "${aws_s3_bucket.this[0].id}"

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

variable "site_domain" {
  description = "Domain on which the static site will be made available"
}

variable "name_prefix" {
  description = "Name prefix to use for objects that need to be created"
  default     = "aws-static-site---"
}

variable "comment_prefix" {
  description = "This will be included in comments for resources that are created"
  default     = "Static site: "
}

variable "bucket_override_name" {
  description = "When provided, assume a bucket with this name already exists"
  default     = ""
}

variable "cloudfront_price_class" {
  description = "CloudFront price class to use"
  default     = 100
}

variable "viewer_https_only" {
  description = "Set this to `false` if you need to support insecure HTTP access"
  default     = true
}

variable "cache_ttl_override" {
  description = "Override the cache behaviour for ALL objects in S3"
  default     = -1
}

variable "default_root_object" {
  description = "The object to return when the root URL is requested"
  default     = "index.html"
}

variable "add_response_headers" {
  description = "Map of HTTP headers to add to outgoing responses"
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
  description = "Displayed by the browser in the auth prompt"
  default     = "Authentication Required"
}

variable "basic_auth_body" {
  description = "Displayed when authentication fails"
  default     = "Unauthorized"
}

variable "lambda_logging_enabled" {
  description = "Write request logs to CloudWatch"
  default     = false
}

variable "tags" {
  description = "AWS Tags to add to all resources"
  type        = "map"
  default     = {}
}

locals {
  prefix_with_domain = "${var.name_prefix}${replace("${var.site_domain}", "/[^a-z0-9-]+/", "-")}"
  bucket_name        = "${var.bucket_override_name == "" ? "${local.prefix_with_domain}" : "${var.bucket_override_name}"}"
  bucket_domain_name = "${local.bucket_name}.s3-website.${data.aws_region.current.name}.amazonaws.com"
  error_ttl          = "${var.cache_ttl_override >= 0 ? var.cache_ttl_override : 0}"
}