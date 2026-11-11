data "aws_route53_zone" "this" {
  name = "${replace("${var.site_domain}", "/.*\\b(\\w+\\.\\w+)\\.?$/", "$1")}" # e.g. "foo.example.com" => "example.com"
}

resource "random_string" "s3_read_password" {
  length  = 32
  special = false
}

module "aws_reverse_proxy" {
  # Available inputs: https://github.com/futurice/terraform-utils/tree/master/aws_reverse_proxy#inputs
  # Check for updates: https://github.com/futurice/terraform-utils/compare/v11.0...master
  source = "git::ssh://git@github.com/futurice/terraform-utils.git//aws_reverse_proxy?ref=v11.0"

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
  value       = "${local.bucket_name}${replace("${element(concat(aws_s3_bucket.this.*.bucket, list("")), 0)}", "/.*/", "")}"
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
  count  = "${var.bucket_override_name == ""? 1 : 0}"
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

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "aws:kms"
        kms_master_key_id = "alias/aws/s3"
      }
    }
  }

  lifecycle_rule {
    id      = "log-bucket-access"
    enabled = true

    transition {
      days          = 30
      storage_class = "GLACIER"
    }

    expiration {
      days = 365
    }
  }

  public_access_block_configuration {
    block_public_acls       = true
    block_public_policy     = true
    ignore_public_acls      = true
    restrict_public_buckets = true
  }

  logging {
    target_bucket = "log-bucket"
    target_prefix = "logs/"
  }
}

resource "aws_s3_bucket_policy" "this" {
  depends_on = ["aws_s3_bucket.this"]
  count      = "${var.bucket_override_name == ""? 1 : 0}"
  bucket     = "${local.bucket_name}"

  policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Deny",
      "Principal": "*",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::${local.bucket_name}/*",
      "Condition": {
        "StringNotEquals": {
          "aws:Referer": [
            "https://www.example.com",
            "https://example.com"
          ]
        }
      }
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
    "Strict-Transport-Security" = "max-age=31557600; preload" # i.e. 1 year (in seconds)
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
  prefix_with_domain = "${var.name_prefix}${replace("${var.site_domain}", "/[^a-z0-9-]+/", "-")}"                          # only lowercase alphanumeric characters and hyphens are allowed in S3 bucket names
  bucket_name        = "${var.bucket_override_name == ""? "${local.prefix_with_domain}" : "${var.bucket_override_name}"}" # select between externally-provided or auto-generated bucket names
  bucket_domain_name = "${local.bucket_name}.s3-website.${data.aws_region.current.name}.amazonaws.com"                     # use current region to complete the domain name (we can't use the "aws_s3_bucket" data source because the bucket may not initially exist)
  error_ttl          = "${var.cache_ttl_override >= 0? var.cache_ttl_override : 0}"
}