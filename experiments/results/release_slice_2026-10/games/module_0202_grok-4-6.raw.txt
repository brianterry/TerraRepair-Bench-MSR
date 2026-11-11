data "aws_route53_zone" "this" {
  name = "${replace("${var.site_domain}", "/.*\\b(\\w+\\.\\w+)\\.?$/", "$1")}" # e.g. "foo.example.com" => "example.com"
}

data "aws_caller_identity" "current" {}

resource "random_string" "s3_read_password" {
  length  = 32
  special = false
}


module "aws_reverse_proxy" {
  # Available inputs: https://github.com/futurice/terraform-utils/tree/master/aws_reverse_proxy#inputs
  # Check for updates: https://github.com/futurice/terraform-utils/compare/v11.0...master
  source = "git::ssh://git@github.com/futurice/terraform-utils.git//aws_reverse_proxy?ref=e3b0c44298fc1c149afbf4c8996fb92427ae41e4"

  # S3 website endpoints are only available over plain HTTP
  origin_url = "http://${local.bucket_domain_name}/"

  # Our S3 bucket will only allow requests containing this custom header
  origin_custom_header_name = "User-Agent"

  # Somewhat perplexingly, this is the "correct" way to ensure users can't bypass CloudFront on their way to S3 resources
  # https://abridge2devnull.com/posts/2018/01/restricting-access-to-a-cloudfront-s3-website-origin/
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

  # Terraform isn't particularly helpful when you want to depend on the existence of a resource which may have count 0 or 1, like our bucket.
  # This is a hacky way of only resolving the bucket_name output once the bucket exists (if created by us).
  # https://github.com/hashicorp/terraform/issues/16580#issuecomment-342573652
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


# Query the current AWS region so we know its S3 endpoint
data "aws_region" "current" {}

resource "aws_kms_key" "this" {
  count                   = "${var.bucket_override_name == "" ? 1 : 0}"
  description             = "${local.prefix_with_domain} S3 CMK"
  deletion_window_in_days = 10
  enable_key_rotation     = true
  tags                    = "${var.tags}"

  policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "EnableRoot",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
      },
      "Action": "kms:*",
      "Resource": "*"
    },
    {
      "Sid": "AllowS3",
      "Effect": "Allow",
      "Principal": {
        "Service": "s3.amazonaws.com"
      },
      "Action": [
        "kms:Decrypt",
        "kms:Encrypt",
        "kms:GenerateDataKey*"
      ],
      "Resource": "*"
    },
    {
      "Sid": "AllowSNS",
      "Effect": "Allow",
      "Principal": {
        "Service": "sns.amazonaws.com"
      },
      "Action": [
        "kms:Decrypt",
        "kms:GenerateDataKey*"
      ],
      "Resource": "*"
    }
  ]
}
POLICY
}

resource "aws_iam_role" "replication" {
  count = "${var.bucket_override_name == "" ? 1 : 0}"
  name  = "${local.prefix_with_domain}-repl"
  tags  = "${var.tags}"

  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "s3.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
POLICY
}

resource "aws_iam_role_policy" "replication" {
  count = "${var.bucket_override_name == "" ? 1 : 0}"
  name  = "${local.prefix_with_domain}-repl"
  role  = "${element(concat(aws_iam_role.replication.*.id, list("")), 0)}"

  policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetReplicationConfiguration",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::${local.bucket_name}",
        "arn:aws:s3:::${local.bucket_name}-r"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObjectVersionForReplication",
        "s3:GetObjectVersionAcl",
        "s3:GetObjectVersionTagging",
        "s3:ReplicateObject",
        "s3:ReplicateDelete",
        "s3:ReplicateTags"
      ],
      "Resource": [
        "arn:aws:s3:::${local.bucket_name}/*",
        "arn:aws:s3:::${local.bucket_name}-r/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "kms:Decrypt",
        "kms:Encrypt",
        "kms:GenerateDataKey*"
      ],
      "Resource": "${element(concat(aws_kms_key.this.*.arn, list("")), 0)}"
    }
  ]
}
POLICY
}

resource "aws_s3_bucket" "replica" {
  count  = "${var.bucket_override_name == "" ? 1 : 0}"
  bucket = "${local.bucket_name}-r"
  tags   = "${var.tags}"

  versioning {
    enabled = true
  }

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        kms_master_key_id = "${element(concat(aws_kms_key.this.*.arn, list("")), 0)}"
        sse_algorithm     = "aws:kms"
      }
    }
  }

  lifecycle_rule {
    id      = "cleanup"
    enabled = true

    abort_incomplete_multipart_upload_days = 7

    noncurrent_version_expiration {
      days = 90
    }
  }

  replication_configuration {
    role = "${element(concat(aws_iam_role.replication.*.arn, list("")), 0)}"

    rules {
      id     = "replicate-all"
      prefix = ""
      status = "Enabled"

      source_selection_criteria {
        sse_kms_encrypted_objects {
          enabled = true
        }
      }

      destination {
        bucket             = "arn:aws:s3:::${local.bucket_name}"
        replica_kms_key_id = "${element(concat(aws_kms_key.this.*.arn, list("")), 0)}"
        storage_class      = "STANDARD"
      }
    }
  }
}

resource "aws_s3_bucket_public_access_block" "replica" {
  count  = "${var.bucket_override_name == "" ? 1 : 0}"
  bucket = "${element(concat(aws_s3_bucket.replica.*.id, list("")), 0)}"

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Create the S3 bucket in which the static content for the site should be hosted
resource "aws_s3_bucket" "this" {
  count  = "${var.bucket_override_name == "" ? 1 : 0}"
  bucket = "${local.bucket_name}"
  tags   = "${var.tags}"

  # Add a CORS configuration, so that we don't have issues with webfont loading
  # http://www.holovaty.com/writing/cors-ie-cloudfront/
  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET"]
    allowed_origins = ["*"]
    max_age_seconds = 3000
  }

  # Enable website hosting
  # Note, though, that when accessing the bucket over its SSL endpoint, the index_document will not be used
  website {
    index_document = "index.html"
    error_document = "error.html"
  }

  versioning {
    enabled = true
  }

  logging {
    target_bucket = "${element(concat(aws_s3_bucket.replica.*.id, list("")), 0)}"
    target_prefix = "logs/"
  }

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        kms_master_key_id = "${element(concat(aws_kms_key.this.*.arn, list("")), 0)}"
        sse_algorithm     = "aws:kms"
      }
    }
  }

  lifecycle_rule {
    id      = "cleanup"
    enabled = true

    abort_incomplete_multipart_upload_days = 7

    noncurrent_version_expiration {
      days = 90
    }
  }

  replication_configuration {
    role = "${element(concat(aws_iam_role.replication.*.arn, list("")), 0)}"

    rules {
      id     = "replicate-all"
      prefix = ""
      status = "Enabled"

      source_selection_criteria {
        sse_kms_encrypted_objects {
          enabled = true
        }
      }

      destination {
        bucket             = "arn:aws:s3:::${local.bucket_name}-r"
        replica_kms_key_id = "${element(concat(aws_kms_key.this.*.arn, list("")), 0)}"
        storage_class      = "STANDARD"
      }
    }
  }
}

resource "aws_s3_bucket_public_access_block" "this" {
  count  = "${var.bucket_override_name == "" ? 1 : 0}"
  bucket = "${element(concat(aws_s3_bucket.this.*.id, list("")), 0)}"

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_sns_topic" "this" {
  count             = "${var.bucket_override_name == "" ? 1 : 0}"
  name              = "${local.prefix_with_domain}-s3-notif"
  kms_master_key_id = "${element(concat(aws_kms_key.this.*.id, list("")), 0)}"
  tags              = "${var.tags}"
}

resource "aws_sns_topic_policy" "this" {
  count = "${var.bucket_override_name == "" ? 1 : 0}"
  arn   = "${element(concat(aws_sns_topic.this.*.arn, list("")), 0)}"

  policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "s3.amazonaws.com"
      },
      "Action": "SNS:Publish",
      "Resource": "${element(concat(aws_sns_topic.this.*.arn, list("")), 0)}",
      "Condition": {
        "ArnLike": {
          "aws:SourceArn": [
            "arn:aws:s3:::${local.bucket_name}",
            "arn:aws:s3:::${local.bucket_name}-r"
          ]
        },
        "StringEquals": {
          "aws:SourceAccount": "${data.aws_caller_identity.current.account_id}"
        }
      }
    }
  ]
}
POLICY
}

resource "aws_s3_bucket_notification" "this" {
  depends_on = ["aws_sns_topic_policy.this"]
  count      = "${var.bucket_override_name == "" ? 1 : 0}"
  bucket     = "${element(concat(aws_s3_bucket.this.*.id, list("")), 0)}"

  topic {
    topic_arn = "${element(concat(aws_sns_topic.this.*.arn, list("")), 0)}"
    events    = ["s3:ObjectCreated:*"]
  }
}

resource "aws_s3_bucket_notification" "replica" {
  depends_on = ["aws_sns_topic_policy.this"]
  count      = "${var.bucket_override_name == "" ? 1 : 0}"
  bucket     = "${element(concat(aws_s3_bucket.replica.*.id, list("")), 0)}"

  topic {
    topic_arn = "${element(concat(aws_sns_topic.this.*.arn, list("")), 0)}"
    events    = ["s3:ObjectCreated:*"]
  }
}

# Use a bucket policy (instead of the simpler acl = "public-read") so we don't need to always remember to upload objects with:
# $ aws s3 cp --acl public-read ...
# https://docs.aws.amazon.com/AmazonS3/latest/dev/acl-overview.html#canned-acl
resource "aws_s3_bucket_policy" "this" {
  depends_on = ["aws_s3_bucket.this", "aws_s3_bucket_public_access_block.this"]
  count      = "${var.bucket_override_name == "" ? 1 : 0}"
  bucket     = "${local.bucket_name}"

  # https://docs.aws.amazon.com/AmazonS3/latest/dev/example-bucket-policies.html#example-bucket-policies-use-case-2
  policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "cloudfront.amazonaws.com"
      },
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::${local.bucket_name}/*",
      "Condition": {
        "StringEquals": {
          "aws:UserAgent": "${random_string.s3_read_password.result}",
          "AWS:SourceAccount": "${data.aws_caller_identity.current.account_id}"
        }
      }
    },
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "logging.s3.amazonaws.com"
      },
      "Action": "s3:PutObject",
      "Resource": "arn:aws:s3:::${local.bucket_name}-r/logs/*",
      "Condition": {
        "StringEquals": {
          "aws:SourceAccount": "${data.aws_caller_identity.current.account_id}"
        },
        "ArnLike": {
          "aws:SourceArn": "arn:aws:s3:::${local.bucket_name}"
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
  bucket_name        = "${var.bucket_override_name == "" ? "${local.prefix_with_domain}" : "${var.bucket_override_name}"}" # select between externally-provided or auto-generated bucket names
  bucket_domain_name = "${local.bucket_name}.s3-website.${data.aws_region.current.name}.amazonaws.com"                     # use current region to complete the domain name (we can't use the "aws_s3_bucket" data source because the bucket may not initially exist)
  error_ttl          = "${var.cache_ttl_override >= 0 ? var.cache_ttl_override : 0}"
}