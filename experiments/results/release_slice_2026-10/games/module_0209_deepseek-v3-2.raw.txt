resource "aws_acm_certificate" "cdn_packages_k8s_io" {
  provider = aws.us-east-1

  domain_name       = "${local.prefix}cdn.packages.k8s.io"
  validation_method = "DNS"

  tags = local.tags

  lifecycle {
    create_before_destroy = true
  }
}

locals {
  s3_origin_id = "${local.prefix}cdn.packages.k8s.io-s3-origin"
}

data "aws_cloudfront_cache_policy" "caching_optimized" {
  name = "Managed-CachingOptimized"
}

resource "aws_cloudfront_origin_access_control" "cdn_packages_k8s_io" {
  name                              = "${local.prefix}cdn.packages.k8s.io"
  description                       = "Control policy for cdn.packages.k8s.io"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "cdn_packages_k8s_io" {
  origin {
    origin_id = local.s3_origin_id

    domain_name              = aws_s3_bucket.cdn_packages_k8s_io.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.cdn_packages_k8s_io.id

    origin_path = ""

    connection_attempts = 3
    connection_timeout  = 10
  }

  enabled             = true
  is_ipv6_enabled     = true
  http_version        = "http2"
  default_root_object = "index.html"
  comment             = "CloudFront used by OpenBuildService (OBS) as a mirror"

  aliases = ["${local.prefix}cdn.packages.k8s.io"]

  web_acl_id = aws_wafv2_web_acl.cdn_packages_k8s_io.arn

  default_cache_behavior {
    target_origin_id = local.s3_origin_id

    cache_policy_id = data.aws_cloudfront_cache_policy.caching_optimized.id

    compress               = true
    viewer_protocol_policy = "https-only"

    allowed_methods = ["GET", "HEAD", "OPTIONS"]
    cached_methods  = ["GET", "HEAD"]
  }

  price_class = "PriceClass_All"

  restrictions {
    geo_restriction {
      restriction_type = "whitelist"
      locations        = ["US", "CA", "GB", "DE", "FR", "JP", "AU", "BR", "IN", "SG"]
    }
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate.cdn_packages_k8s_io.arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  logging_config {
    bucket          = "${aws_s3_bucket.cdn_packages_k8s_io_logs.bucket}.s3.amazonaws.com"
    include_cookies = false
    prefix          = "cloudfront-logs/"
  }

  depends_on = [
    aws_acm_certificate.cdn_packages_k8s_io,
    aws_cloudfront_origin_access_control.cdn_packages_k8s_io,
    aws_wafv2_web_acl.cdn_packages_k8s_io,
    aws_s3_bucket.cdn_packages_k8s_io,
    aws_s3_bucket.cdn_packages_k8s_io_logs,
  ]

  tags = local.tags
}

terraform {
  backend "s3" {
    bucket       = "cdn-packages-k8s-io-tfstate"
    key          = "terraform.tfstate"
    region       = "eu-central-1"
    role_arn     = "arn:aws:iam::309501585971:role/Provisioner"
    session_name = "cdn-packages-k8s-io-terraform"
  }

  required_version = "~> 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.7"
    }
  }
}

provider "aws" {
  region = var.region

  assume_role {
    role_arn     = "arn:aws:iam::309501585971:role/Provisioner"
    session_name = "cdn-packages-k8s-io-terraform"
  }
}

provider "aws" {
  region = "us-east-1"
  alias  = "us-east-1"

  assume_role {
    role_arn     = "arn:aws:iam::309501585971:role/Provisioner"
    session_name = "cdn-packages-k8s-io-terraform"
  }
}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id

  prefix = "${terraform.workspace}-"

  tags = {
    project = "cdn.packages.k8s.io"
  }
}

resource "aws_s3_bucket" "cdn_packages_k8s_io" {
  bucket = "${local.prefix}cdn-packages-k8s-io-${data.aws_region.current.name}"

  tags = local.tags
}

resource "aws_s3_bucket" "cdn_packages_k8s_io_logs" {
  bucket = "${local.prefix}cdn-packages-k8s-io-logs-${data.aws_region.current.name}"

  tags = local.tags
}

resource "aws_s3_bucket_ownership_controls" "cdn_packages_k8s_io" {
  bucket = aws_s3_bucket.cdn_packages_k8s_io.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }

  depends_on = [
    aws_s3_bucket.cdn_packages_k8s_io,
  ]
}

resource "aws_s3_bucket_ownership_controls" "cdn_packages_k8s_io_logs" {
  bucket = aws_s3_bucket.cdn_packages_k8s_io_logs.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }

  depends_on = [
    aws_s3_bucket.cdn_packages_k8s_io_logs,
  ]
}

resource "aws_s3_bucket_versioning" "cdn_packages_k8s_io" {
  bucket = aws_s3_bucket.cdn_packages_k8s_io.id

  versioning_configuration {
    status = "Enabled"
  }

  depends_on = [
    aws_s3_bucket.cdn_packages_k8s_io,
  ]
}

resource "aws_s3_bucket_versioning" "cdn_packages_k8s_io_logs" {
  bucket = aws_s3_bucket.cdn_packages_k8s_io_logs.id

  versioning_configuration {
    status = "Enabled"
  }

  depends_on = [
    aws_s3_bucket.cdn_packages_k8s_io_logs,
  ]
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cdn_packages_k8s_io" {
  bucket = aws_s3_bucket.cdn_packages_k8s_io.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.cdn_packages_k8s_io.arn
      sse_algorithm     = "aws:kms"
    }
  }

  depends_on = [
    aws_s3_bucket.cdn_packages_k8s_io,
  ]
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cdn_packages_k8s_io_logs" {
  bucket = aws_s3_bucket.cdn_packages_k8s_io_logs.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.cdn_packages_k8s_io.arn
      sse_algorithm     = "aws:kms"
    }
  }

  depends_on = [
    aws_s3_bucket.cdn_packages_k8s_io_logs,
  ]
}

resource "aws_s3_bucket_logging" "cdn_packages_k8s_io" {
  bucket = aws_s3_bucket.cdn_packages_k8s_io.id

  target_bucket = aws_s3_bucket.cdn_packages_k8s_io_logs.id
  target_prefix = "s3-logs/"
}

resource "aws_s3_bucket_lifecycle_configuration" "cdn_packages_k8s_io" {
  bucket = aws_s3_bucket.cdn_packages_k8s_io.id

  rule {
    id     = "log"
    status = "Enabled"

    filter {
      prefix = "s3-logs/"
    }

    expiration {
      days = 365
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  depends_on = [
    aws_s3_bucket.cdn_packages_k8s_io,
  ]
}

resource "aws_s3_bucket_lifecycle_configuration" "cdn_packages_k8s_io_logs" {
  bucket = aws_s3_bucket.cdn_packages_k8s_io_logs.id

  rule {
    id     = "log"
    status = "Enabled"

    filter {
      prefix = "cloudfront-logs/"
    }

    expiration {
      days = 365
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  depends_on = [
    aws_s3_bucket.cdn_packages_k8s_io_logs,
  ]
}

resource "aws_s3_bucket_public_access_block" "cdn_packages_k8s_io" {
  bucket = aws_s3_bucket.cdn_packages_k8s_io.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true

  depends_on = [
    aws_s3_bucket.cdn_packages_k8s_io,
  ]
}

resource "aws_s3_bucket_public_access_block" "cdn_packages_k8s_io_logs" {
  bucket = aws_s3_bucket.cdn_packages_k8s_io_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true

  depends_on = [
    aws_s3_bucket.cdn_packages_k8s_io_logs,
  ]
}

resource "aws_s3_bucket_policy" "cdn_packages_k8s_io_cloudfront_read" {
  bucket = aws_s3_bucket.cdn_packages_k8s_io.bucket

  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : {
      "Sid" : "AllowCloudFrontServicePrincipalReadOnly",
      "Effect" : "Allow",
      "Principal" : {
        "Service" : "cloudfront.amazonaws.com"
      },
      "Action" : "s3:GetObject",
      "Resource" : "arn:aws:s3:::${aws_s3_bucket.cdn_packages_k8s_io.bucket}/*",
      "Condition" : {
        "StringEquals" : {
          "AWS:SourceArn" : "arn:aws:cloudfront::${local.account_id}:distribution/${aws_cloudfront_distribution.cdn_packages_k8s_io.id}"
        }
      }
    }
  })

  depends_on = [
    aws_s3_bucket.cdn_packages_k8s_io,
    aws_cloudfront_distribution.cdn_packages_k8s_io,
  ]
}

resource "aws_kms_key" "cdn_packages_k8s_io" {
  description             = "KMS key for encrypting S3 bucket cdn-packages-k8s-io"
  deletion_window_in_days = 10
  enable_key_rotation     = true

  tags = local.tags
}

variable "region" {
  type        = string
  nullable    = false
  description = "Region where to deploy non-global resources (e.g. S3 bucket)"
}

resource "aws_wafv2_web_acl" "cdn_packages_k8s_io" {
  provider = aws.us-east-1

  name        = "${local.prefix}PackagesCloudFrontWebACL"
  description = "WAF Web ACL used by cdn.packages.k8s.io CloudFront."
  scope       = "CLOUDFRONT"

  default_action {
    allow {}
  }

  rule {
    name     = "AWS-AWSManagedRulesAmazonIpReputationList"
    priority = 0

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesAmazonIpReputationList"
        vendor_name = "AWS"
      }
    }

    override_action {
      none {}
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      sampled_requests_enabled   = true
      metric_name                = "AWS-AWSManagedRulesAmazonIpReputationList"
    }
  }

  rule {
    name     = "AWS-AWSManagedRulesCommonRuleSet"
    priority = 1

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"

        rule_action_override {
          name = "UserAgent_BadBots_HEADER"

          action_to_use {
            count {}
          }
        }

        rule_action_override {
          name = "NoUserAgent_HEADER"

          action_to_use {
            count {}
          }
        }
      }
    }

    override_action {
      none {}
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      sampled_requests_enabled   = true
      metric_name                = "AWS-AWSManagedRulesCommonRuleSet"
    }
  }

  rule {
    name     = "AWS-AWSManagedRulesKnownBadInputsRuleSet"
    priority = 2

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }

    override_action {
      none {}
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      sampled_requests_enabled   = true
      metric_name                = "AWS-AWSManagedRulesKnownBadInputsRuleSet"
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    sampled_requests_enabled   = true
    metric_name                = "${local.prefix}PackagesCloudFrontWebACL"
  }

  logging_configuration {
    log_destination_configs = ["arn:aws:s3:::${aws_s3_bucket.cdn_packages_k8s_io_logs.bucket}/waf-logs/"]
  }

  tags = local.tags
}