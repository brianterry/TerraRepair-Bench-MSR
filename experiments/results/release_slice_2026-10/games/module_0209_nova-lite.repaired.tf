/*
Copyright 2023 The Kubernetes Authors.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

resource "aws_acm_certificate" "cdn_packages_k8s_io" {
  # ACM certificate for CloudFront distribution must be created in us-east-1 (required by AWS)
  provider = aws.us-east-1

  domain_name       = "${local.prefix}cdn.packages.k8s.io"
  validation_method = "DNS"

  tags = local.tags

  lifecycle {
    create_before_destroy = true
  }
}


/*
Copyright 2023 The Kubernetes Authors.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

locals {
  s3_origin_id = "${local.prefix}cdn.packages.k8s.io-s3-origin"
}

data "aws_cloudfront_cache_policy" "caching_optimized" {
  # CachingOptmizied is recommended for S3
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

  aliases = ["${local.prefix}cdn.packages.k8s.io"]

  web_acl_id = aws_wafv2_web_acl.cdn_packages_k8s_io.arn

  default_cache_behavior {
    target_origin_id = local.s3_origin_id

    cache_policy_id = data.aws_cloudfront_cache_policy.caching_optimized.id

    compress               = true
    viewer_protocol_policy = "redirect-to-https"

    allowed_methods = ["GET", "HEAD", "OPTIONS"]
    cached_methods  = ["GET", "HEAD"]
  }

  price_class = "PriceClass_All"

  restrictions {
    geo_restriction {
      restriction_type = "whitelist"
      locations        = ["US", "CA"]
    }
  }

  viewer_certificate {
    acm_certificate_arn = aws_acm_certificate.cdn_packages_k8s_io.arn
    ssl_support_method  = "sni-only"
    minimum_protocol_version = "TLSv1.2_2019"
  }

  logging {
    enabled = true
    bucket  = aws_s3_bucket.cdn_packages_k8s_io.bucket
    prefix  = "cloudfront-logs/"
  }

  origin_failover {
    primary_origin {
      origin_id = local.s3_origin_id
    }

    secondary_origin {
      origin_id = "secondary-origin-id"
      domain_name = "secondary-bucket.s3.amazonaws.com"
    }

    failover_criteria {
      number_of_errors = 10
    }
  }

  response_headers_policy_id = aws_cloudfront_response_headers_policy.cdn_packages_k8s_io.id

  depends_on = [
    aws_acm_certificate.cdn_packages_k8s_io,
    aws_cloudfront_origin_access_control.cdn_packages_k8s_io,
    aws_wafv2_web_acl.cdn_packages_k8s_io,
    aws_s3_bucket.cdn_packages_k8s_io,
  ]

  tags = local.tags
}

resource "aws_cloudfront_response_headers_policy" "cdn_packages_k8s_io" {
  name = "cdn-packages-k8s-io-response-headers-policy"

  cors_policy {
    access_control_allow_credentials = true
    access_control_allow_headers      = ["*"]
    access_control_allow_methods      = ["GET", "HEAD", "OPTIONS"]
    access_control_allow_origins      = ["*"]
    access_control_max_age_sec        = 3600
  }

  comment = "Response headers policy for cdn.packages.k8s.io"
}

/*
Copyright 2023 The Kubernetes Authors.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

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

# ACM certificate for CloudFront distribution must be created in us-east-1 (required by AWS)
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


/*
Copyright 2023 The Kubernetes Authors.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

resource "aws_s3_bucket" "cdn_packages_k8s_io" {
  bucket = "${local.prefix}cdn-packages-k8s-io-${data.aws_region.current.name}"

  tags = local.tags
}

# This object ownership control ensures that ACLs are disabled for the bucket.
resource "aws_s3_bucket_ownership_controls" "cdn_packages_k8s_io" {
  bucket = aws_s3_bucket.cdn_packages_k8s_io.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }

  depends_on = [
    aws_s3_bucket.cdn_packages_k8s_io,
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

resource "aws_s3_bucket_public_access_block" "cdn_packages_k8s_io" {
  bucket = aws_s3_bucket.cdn_packages_k8s_io.id

  block_public_acls      = true
  block_public_policy   = true
  ignore_public_acls     = false
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cdn_packages_k8s_io" {
  bucket = aws_s3_bucket.cdn_packages_k8s_io.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
      kms_master_key_id = "alias/aws/s3"
    }
  }
}

resource "aws_s3_bucket_logging" "cdn_packages_k8s_io" {
  bucket = aws_s3_bucket.cdn_packages_k8s_io.id

  target_bucket = aws_s3_bucket.cdn_packages_k8s_io.id
  target_prefix = "logs/"

  depends_on = [
    aws_s3_bucket.cdn_packages_k8s_io,
  ]
}

resource "aws_s3_bucket_policy" "cdn_packages_k8s_io_cloudfront_read" {
  bucket = aws_s3_bucket.cdn_packages_k8s_io.bucket

  # Source: https://docs.aws.amazon.com/whitepapers/latest/secure-content-delivery-amazon-cloudfront/s3-origin-with-cloudfront.html
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


/*
Copyright 2023 The Kubernetes Authors.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

variable "region" {
  type        = string
  nullable    = false
  description = "Region where to deploy non-global resources (e.g. S3 bucket)"
}


/*
Copyright 2023 The Kubernetes Authors.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

resource "aws_wafv2_web_acl" "cdn_packages_k8s_io" {
  # WAF Web ACLs for CloudFront distribution must be created in us-east-1 (required by AWS)
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

        // Older yum versions (e.g. 3.4.3 used on CentOS 7) are triggering
        // this rule which makes yum fail with 403 Forbidden.
        rule_action_override {
          name = "UserAgent_BadBots_HEADER"

          action_to_use {
            count {}
          }
        }

        // tdnf used on Photon OS doesn't send a user agent header so
        // this rule is being triggered which makes tdnf fail with 403 Forbidden.
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

  tags = local.tags
}