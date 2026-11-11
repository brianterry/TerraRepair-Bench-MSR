provider "aws" {
  region  = var.region
  version = "~> 3.64"
}

terraform {
  required_version = "~> 0.12"
}

provider "aws" {
  alias   = "us_east_1" #cloudfront needs acm certificate to be from "us-east-1" region
  region  = "us-east-1"
  version = "~> 3.64"
}

provider "aws" {
  alias   = "replica"
  region  = "us-west-2"
  version = "~> 3.64"
}


## ACM Certificate
data "aws_route53_zone" "this" {
  name = replace(var.site_domain, "/.*\\b(\\w+\\.\\w+)\\.?$/", "$1") # gets domain from subdomain e.g. "foo.example.com" => "example.com"
}

module "acm" {
  source      = "git::https://github.com/terraform-aws-modules/terraform-aws-acm.git?ref=64b5ac3c0f887893a4b70c12a97f3a0fe55766ac"
  domain_name = var.site_domain
  zone_id     = data.aws_route53_zone.this.zone_id
  tags        = var.tags

  providers = {
    aws = "aws.us_east_1" # cloudfront needs acm certificate to be from "us-east-1" region
  }
}

data "aws_caller_identity" "current" {}

resource "aws_kms_key" "this" {
  description             = "CMK for S3 bucket encryption"
  deletion_window_in_days = 10
  enable_key_rotation     = true
  tags                    = var.tags
}

resource "aws_kms_key" "replica" {
  provider                = aws.replica
  description             = "CMK for replica S3 bucket encryption"
  deletion_window_in_days = 10
  enable_key_rotation     = true
  tags                    = var.tags
}

resource "aws_s3_bucket" "logs" {
  bucket = "${var.bucket_name}-logs"
  acl    = "log-delivery-write"
  tags   = var.tags
}

resource "aws_s3_bucket" "replica" {
  provider = aws.replica
  bucket   = "${var.bucket_name}-replica"
  tags     = var.tags

  versioning {
    enabled = true
  }

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm     = "aws:kms"
        kms_master_key_id = aws_kms_key.replica.arn
      }
      bucket_key_enabled = true
    }
  }
}

data "aws_iam_policy_document" "replication_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["s3.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "replication" {
  name               = "${var.bucket_name}-replication"
  assume_role_policy = data.aws_iam_policy_document.replication_assume.json
  tags               = var.tags
}

data "aws_iam_policy_document" "replication" {
  statement {
    actions = [
      "s3:GetReplicationConfiguration",
      "s3:ListBucket"
    ]
    resources = [aws_s3_bucket.this.arn]
  }

  statement {
    actions = [
      "s3:GetObjectVersionForReplication",
      "s3:GetObjectVersionAcl",
      "s3:GetObjectVersionTagging"
    ]
    resources = ["${aws_s3_bucket.this.arn}/*"]
  }

  statement {
    actions = [
      "s3:ReplicateObject",
      "s3:ReplicateDelete",
      "s3:ReplicateTags"
    ]
    resources = ["${aws_s3_bucket.replica.arn}/*"]
  }

  statement {
    actions   = ["kms:Decrypt"]
    resources = [aws_kms_key.this.arn]
  }

  statement {
    actions   = ["kms:Encrypt"]
    resources = [aws_kms_key.replica.arn]
  }
}

resource "aws_iam_role_policy" "replication" {
  name   = "${var.bucket_name}-replication"
  role   = aws_iam_role.replication.id
  policy = data.aws_iam_policy_document.replication.json
}

## S3
resource "aws_s3_bucket" "this" {
  bucket = var.bucket_name
  tags   = var.tags

  versioning {
    enabled = true
  }

  logging {
    target_bucket = aws_s3_bucket.logs.id
    target_prefix = "s3/"
  }

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm     = "aws:kms"
        kms_master_key_id = aws_kms_key.this.arn
      }
      bucket_key_enabled = true
    }
  }

  lifecycle_rule {
    id      = "expire-old-versions"
    enabled = true

    noncurrent_version_expiration {
      days = 90
    }
  }

  replication_configuration {
    role = aws_iam_role.replication.arn

    rules {
      id     = "replicate-all"
      status = "Enabled"
      prefix = ""

      destination {
        bucket             = aws_s3_bucket.replica.arn
        replica_kms_key_id = aws_kms_key.replica.arn
      }

      source_selection_criteria {
        sse_kms_encrypted_objects {
          enabled = true
        }
      }
    }
  }
}

resource "aws_s3_bucket_public_access_block" "website_bucket" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

data "aws_iam_policy_document" "s3_policy_document" {
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.this.arn}/*"]

    principals {
      type        = "AWS"
      identifiers = [aws_cloudfront_origin_access_identity.this.iam_arn]
    }
  }

  statement {
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.this.arn]

    principals {
      type        = "AWS"
      identifiers = [aws_cloudfront_origin_access_identity.this.iam_arn]
    }
  }
}

resource "aws_s3_bucket_policy" "s3_policy" {
  bucket = aws_s3_bucket.this.id
  policy = data.aws_iam_policy_document.s3_policy_document.json
}

data "aws_iam_policy_document" "replica_policy_document" {
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.replica.arn}/*"]

    principals {
      type        = "AWS"
      identifiers = [aws_cloudfront_origin_access_identity.this.iam_arn]
    }
  }

  statement {
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.replica.arn]

    principals {
      type        = "AWS"
      identifiers = [aws_cloudfront_origin_access_identity.this.iam_arn]
    }
  }
}

resource "aws_s3_bucket_policy" "replica" {
  provider = aws.replica
  bucket   = aws_s3_bucket.replica.id
  policy   = data.aws_iam_policy_document.replica_policy_document.json
}

resource "aws_sns_topic" "this" {
  name = "${var.bucket_name}-s3-events"
  tags = var.tags
}

data "aws_iam_policy_document" "sns" {
  statement {
    actions   = ["SNS:Publish"]
    resources = [aws_sns_topic.this.arn]

    principals {
      type        = "Service"
      identifiers = ["s3.amazonaws.com"]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = [aws_s3_bucket.this.arn]
    }
  }
}

resource "aws_sns_topic_policy" "this" {
  arn    = aws_sns_topic.this.arn
  policy = data.aws_iam_policy_document.sns.json
}

resource "aws_s3_bucket_notification" "this" {
  bucket = aws_s3_bucket.this.id

  topic {
    topic_arn = aws_sns_topic.this.arn
    events    = ["s3:ObjectCreated:*"]
  }

  depends_on = [aws_sns_topic_policy.this]
}

resource "aws_wafv2_web_acl" "this" {
  provider    = aws.us_east_1
  name        = "${var.bucket_name}-waf"
  description = "WAF for CloudFront"
  scope       = "CLOUDFRONT"
  tags        = var.tags

  default_action {
    allow {}
  }

  rule {
    name     = "AWSManagedRulesKnownBadInputsRuleSet"
    priority = 1

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWSManagedRulesKnownBadInputsRuleSet"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.bucket_name}-waf"
    sampled_requests_enabled   = true
  }
}

## Cloudfront

resource "aws_cloudfront_origin_access_identity" "this" {
  comment = "Origin Access Identity used to access S3 for ${var.site_domain}"
}


resource "aws_cloudfront_distribution" "this" {
  origin {
    domain_name = aws_s3_bucket.this.bucket_regional_domain_name
    origin_id   = local.s3_origin_id

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.this.cloudfront_access_identity_path
    }
  }

  origin {
    domain_name = aws_s3_bucket.replica.bucket_regional_domain_name
    origin_id   = local.s3_failover_origin_id

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.this.cloudfront_access_identity_path
    }
  }

  origin_group {
    origin_id = local.s3_origin_group_id

    failover_criteria {
      status_codes = [403, 404, 500, 502, 503, 504]
    }

    member {
      origin_id = local.s3_origin_id
    }

    member {
      origin_id = local.s3_failover_origin_id
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  comment             = var.site_domain
  default_root_object = var.default_root_object
  web_acl_id          = aws_wafv2_web_acl.this.arn

  aliases = [var.site_domain]

  logging_config {
    include_cookies = false
    bucket          = aws_s3_bucket.logs.bucket_domain_name
    prefix          = "cloudfront/"
  }

  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = local.s3_origin_group_id

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy     = "redirect-to-https"
    min_ttl                    = var.min_ttl
    default_ttl                = var.default_ttl
    max_ttl                    = var.max_ttl
    response_headers_policy_id = "67f7725c-6f97-4210-82d7-5512b31e9d03"
  }
  price_class = var.cf_price_class

  tags = var.tags

  restrictions {
    geo_restriction {
      restriction_type = "blacklist"
      locations        = ["KP", "IR", "CU", "SY"]
    }
  }


  viewer_certificate {
    acm_certificate_arn      = module.acm.this_acm_certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  # By default, cloudfront caches error for five minutes. There can be situation when a developer has accidentally broken the website and you would not want to wait for five minutes for the error response to be cached.
  # https://docs.aws.amazon.com/AmazonS3/latest/dev/CustomErrorDocSupport.html
  custom_error_response {
    error_code            = 400
    error_caching_min_ttl = var.error_ttl
  }

  custom_error_response {
    error_code            = 403
    error_caching_min_ttl = var.error_ttl
  }

  custom_error_response {
    error_code            = 404
    error_caching_min_ttl = var.error_ttl
  }

  custom_error_response {
    error_code            = 405
    error_caching_min_ttl = var.error_ttl
  }

}



## Route53
# Add an IPv4 DNS record pointing to the CloudFront distribution
resource "aws_route53_record" "ipv4" {
  zone_id = data.aws_route53_zone.this.zone_id
  name    = var.site_domain
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.this.domain_name
    zone_id                = aws_cloudfront_distribution.this.hosted_zone_id
    evaluate_target_health = false
  }
}

# Add an IPv6 DNS record pointing to the CloudFront distribution
resource "aws_route53_record" "ipv6" {
  zone_id = data.aws_route53_zone.this.zone_id
  name    = var.site_domain
  type    = "AAAA"

  alias {
    name                   = aws_cloudfront_distribution.this.domain_name
    zone_id                = aws_cloudfront_distribution.this.hosted_zone_id
    evaluate_target_health = false
  }
}


variable "region" {
  description = "THe primary AWS region where all the resources will be created. See https://docs.aws.amazon.com/general/latest/gr/rande.html"
}

variable "tags" {
  description = "AWS Tags to add to all resources created (where possible); see https://aws.amazon.com/answers/account-management/aws-tagging-strategies/"
  type        = "map"
  default     = {}
}

variable "site_domain" {
  description = "The primary domain name of the website"
}

variable "bucket_name" {
  description = "The name of the S3 bucket wich would host the static files"
}

variable "cf_price_class" {
  description = "TThe price class for this distribution. One of PriceClass_All, PriceClass_200, PriceClass_100"
  default     = "PriceClass_100"
}

variable "default_root_object" {
  description = "The object to return when the root URL is requested"
  default     = "index.html"
}


variable "default_ttl" {
  description = "The default amount of time (in secs) that an object is cached in cloudfront in the absence of Cache-Control max-age or Expires header."
  default     = "86400"
}

variable "max_ttl" {
  description = "The maximum amount of time (in secs) that an object is cached in cloudfront before cloudfront forwards another request ot origin to determine if the object has been updated."
  default     = "31536000" # 365 days
}

variable "min_ttl" {
  description = "The minimum amount of time (in secs) that an object is cached in cloudfront before cloudfront forwards another request ot origin to determine if the object has been updated."
  default     = "0"
}

variable "error_ttl" {
  description = "The minimum amount of time (in secs) that cloudfront caches an HTTP error code."
  default     = "30"
}


locals {
  s3_origin_id          = "myS3Origin"
  s3_failover_origin_id = "myS3FailoverOrigin"
  s3_origin_group_id    = "myS3OriginGroup"
}