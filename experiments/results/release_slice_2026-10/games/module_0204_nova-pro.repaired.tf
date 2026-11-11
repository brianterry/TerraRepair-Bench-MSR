provider "aws" {
  region  = var.region
  version = "~> 2.0"
}

terraform {
  required_version = "~> 0.12"
}

provider "aws" {
  alias   = "us_east_1"
  region  = "us-east-1"
  version = "~> 2.0"
}

data "aws_route53_zone" "this" {
  name = replace(var.site_domain, "/.*\\b(\\w+\\.\\w+)\\.?$/", "$1")
}

module "acm" {
  source      = "terraform-aws-modules/acm/aws"
  version     = "~> v2.0"
  domain_name = var.site_domain
  zone_id     = data.aws_route53_zone.this.zone_id
  tags        = var.tags

  providers = {
    aws = "aws.us_east_1"
  }
}

resource "aws_s3_bucket" "this" {
  bucket                   = var.bucket_name
  tags                     = var.tags
  versioning               = {
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
  logging {
    target_bucket = var.bucket_name
    target_prefix = "logs/"
  }
}

resource "aws_s3_bucket_public_access_block" "website_bucket" {
  bucket                   = aws_s3_bucket.this.id
  block_public_acls        = true
  ignore_public_acls       = true
  block_public_policy      = true
  restrict_public_buckets  = true
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
  enabled             = true
  is_ipv6_enabled     = true
  comment             = var.site_domain
  default_root_object = var.default_root_object
  aliases             = [var.site_domain]
  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = local.s3_origin_id
    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = var.min_ttl
    default_ttl            = var.default_ttl
    max_ttl                = var.max_ttl
  }
  price_class = var.cf_price_class
  tags        = var.tags
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
  viewer_certificate {
    acm_certificate_arn      = module.acm.this_acm_certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2019"
  }
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
  web_acl_id = "arn:aws:wafv2:us-east-1:123456789012:global/webacl/example-web-acl/473efc7a-1e24-4966-98d9-123456789abc"
  enabled = true
  logging {
    bucket = aws_s3_bucket.this.bucket
    include_cookies = false
  }
}

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
  description = "The primary AWS region where all the resources will be created."
}

variable "tags" {
  description = "AWS Tags to add to all resources created (where possible)."
  type        = "map"
  default     = {}
}

variable "site_domain" {
  description = "The primary domain name of the website."
}

variable "bucket_name" {
  description = "The name of the S3 bucket which would host the static files."
}

variable "cf_price_class" {
  description = "The price class for this distribution."
  default     = "PriceClass_100"
}

variable "default_root_object" {
  description = "The object to return when the root URL is requested."
  default     = "index.html"
}

variable "default_ttl" {
  description = "The default amount of time (in secs) that an object is cached in cloudfront."
  default     = "86400"
}

variable "max_ttl" {
  description = "The maximum amount of time (in secs) that an object is cached in cloudfront."
  default     = "31536000"
}

variable "min_ttl" {
  description = "The minimum amount of time (in secs) that an object is cached in cloudfront."
  default     = "0"
}

variable "error_ttl" {
  description = "The minimum amount of time (in secs) that cloudfront caches an HTTP error code."
  default     = "30"
}

locals {
  s3_origin_id = "myS3Origin"
}