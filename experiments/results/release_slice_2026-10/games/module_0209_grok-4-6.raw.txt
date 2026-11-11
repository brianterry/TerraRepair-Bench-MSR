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
  s3_origin_id          = "${local.prefix}cdn.packages.k8s.io-s3-origin"
  s3_origin_failover_id = "${local.prefix}cdn.packages.k8s.io-s3-origin-failover"
  s3_origin_group_id    = "${local.prefix}cdn.packages.k8s.io-s3-origin-group"
}

data "aws_cloudfront_cache_policy" "caching_optimized" {
  # CachingOptmizied is recommended for S3
  name = "Managed-CachingOptimized"
}

data "aws_cloudfront_response_headers_policy" "security_headers" {
  name = "Managed-SecurityHeadersPolicy"
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

  origin {
    origin_id = local.s3_origin_failover_id

    domain_name              = aws_s3_bucket.cdn_packages_k8s_io.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.cdn_packages_k8s_io.id

    origin_path = ""

    connection_attempts = 3
    connection_timeout  = 10
  }

  origin_group {
    origin_id = local.s3_origin_group_id

    failover_criteria {
      status_codes = [500, 502, 503, 504]
    }

    member {
      origin_id = local.s3_origin_id
    }

    member {
      origin_id = local.s3_origin_failover_id
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  http_version        = "http2"
  default_root_object = "index.html"
  comment             = "CloudFront used by OpenBuildService (OBS) as a mirror"

  aliases = ["${local.prefix}cdn.packages.k8s.io"]

  web_acl_id = aws_wafv2_web_acl.cdn_packages_k8s_io.arn

  logging_config {
    include_cookies = false
    bucket          = aws_s3_bucket.cdn_packages_k8s_io_logs.bucket_domain_name
    prefix          = "cloudfront/"
  }

  default_cache_behavior {
    target_origin_id = local.s3_origin_group_id

    cache_policy_id            = data.aws_cloudfront_cache_policy.caching_optimized.id
    response_headers_policy_id = data.aws_cloudfront_response_headers_policy.security_headers.id

    compress               = true
    viewer_protocol_policy = "redirect-to-https"

    allowed_methods = ["GET", "HEAD", "OPTIONS"]
    cached_methods  = ["GET", "HEAD"]
  }

  price_class = "PriceClass_All"

  restrictions {
    geo_restriction {
      restriction_type = "blacklist"
      locations        = ["CU", "IR", "KP", "SY"]
    }
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate.cdn_packages_k8s_io.arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  depends_on = [
    aws_acm_certificate.cdn_packages_k8s_io,
    aws_cloudfront_origin_access_control.cdn_packages_k8s_io,
    aws_wafv2_web_acl.cdn_packages_k8s_io,
    aws_s3_bucket.cdn_packages_k8s_io,
    aws_s3_bucket.cdn_packages_k8s_io_logs,
    aws_s3_bucket_acl.cdn_packages_k8s_io_logs,
  ]

  tags = local.tags
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

data "aws_canonical_user_id" "current" {}

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

resource "aws_kms_key" "cdn_packages_k8s_io" {
  description             = "CMK for cdn.packages.k8s.io S3 encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${local.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow CloudFront to use the key"
        Effect = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action = [
          "kms:Decrypt",
          "kms:Encrypt",
          "kms:GenerateDataKey*"
        ]
        Resource = "*"
      },
      {
        Sid    = "Allow S3 Log Delivery to use the key"
        Effect = "Allow"
        Principal = {
          Service = "logging.s3.amazonaws.com"
        }
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = "*"
      }
    ]
  })

  tags = local.tags
}

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

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true

  depends_on = [
    aws_s3_bucket.cdn_packages_k8s_io,
  ]
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cdn_packages_k8s_io" {
  bucket = aws_s3_bucket.cdn_packages_k8s_io.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.cdn_packages_k8s_io.arn
      sse_algorithm     = "aws:kms"
    }
    bucket_key_enabled = true
  }

  depends_on = [
    aws_s3_bucket.cdn_packages_k8s_io,
    aws_kms_key.cdn_packages_k8s_io,
  ]
}

resource "aws_s3_bucket_logging" "cdn_packages_k8s_io" {
  bucket = aws_s3_bucket.cdn_packages_k8s_io.id

  target_bucket = aws_s3_bucket.cdn_packages_k8s_io_logs.id
  target_prefix = "s3-access-logs/"

  depends_on = [
    aws_s3_bucket.cdn_packages_k8s_io,
    aws_s3_bucket.cdn_packages_k8s_io_logs,
    aws_s3_bucket_policy.cdn_packages_k8s_io_logs,
  ]
}

resource "aws_s3_bucket_lifecycle_configuration" "cdn_packages_k8s_io" {
  bucket = aws_s3_bucket.cdn_packages_k8s_io.id

  rule {
    id     = "lifecycle-policy"
    status = "Enabled"

    filter {
      prefix = ""
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }

    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }

  depends_on = [
    aws_s3_bucket.cdn_packages_k8s_io,
    aws_s3_bucket_versioning.cdn_packages_k8s_io,
  ]
}

resource "aws_s3_bucket" "cdn_packages_k8s_io_logs" {
  bucket = "${local.prefix}cdn-packages-k8s-io-logs-${data.aws_region.current.name}"

  tags = local.tags
}

resource "aws_s3_bucket_ownership_controls" "cdn_packages_k8s_io_logs" {
  bucket = aws_s3_bucket.cdn_packages_k8s_io_logs.id

  rule {
    object_ownership = "BucketOwnerPreferred"
  }

  depends_on = [
    aws_s3_bucket.cdn_packages_k8s_io_logs,
  ]
}

resource "aws_s3_bucket_acl" "cdn_packages_k8s_io_logs" {
  bucket = aws_s3_bucket.cdn_packages_k8s_io_logs.id

  access_control_policy {
    grant {
      grantee {
        id   = data.aws_canonical_user_id.current.id
        type = "CanonicalUser"
      }
      permission = "FULL_CONTROL"
    }

    grant {
      grantee {
        id   = "c4c1ede66af53448b93c283ce9448c4ba468c9432aa01d700d3878632f77d2d0"
        type = "CanonicalUser"
      }
      permission = "FULL_CONTROL"
    }

    grant {
      grantee {
        type = "Group"
        uri  = "http://acs.amazonaws.com/groups/s3/LogDelivery"
      }
      permission = "WRITE"
    }

    grant {
      grantee {
        type = "Group"
        uri  = "http://acs.amazonaws.com/groups/s3/LogDelivery"
      }
      permission = "READ_ACP"
    }

    owner {
      id = data.aws_canonical_user_id.current.id
    }
  }

  depends_on = [
    aws_s3_bucket_ownership_controls.cdn_packages_k8s_io_logs,
  ]
}

resource "aws_s3_bucket_public_access_block" "cdn_packages_k8s_io_logs" {
  bucket = aws_s3_bucket.cdn_packages_k8s_io_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true

  depends_on = [
    aws_s3_bucket_acl.cdn_packages_k8s_io_logs,
  ]
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cdn_packages_k8s_io_logs" {
  bucket = aws_s3_bucket.cdn_packages_k8s_io_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }

  depends_on = [
    aws_s3_bucket.cdn_packages_k8s_io_logs,
  ]
}

resource "aws_s3_bucket_policy" "cdn_packages_k8s_io_logs" {
  bucket = aws_s3_bucket.cdn_packages_k8s_io_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowS3LogDelivery"
        Effect = "Allow"
        Principal = {
          Service = "logging.s3.amazonaws.com"
        }
        Action   = ["s3:PutObject"]
        Resource = "${aws_s3_bucket.cdn_packages_k8s_io_logs.arn}/s3-access-logs/*"
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = local.account_id
          }
        }
      }
    ]
  })

  depends_on = [
    aws_s3_bucket.cdn_packages_k8s_io_logs,
    aws_s3_bucket_public_access_block.cdn_packages_k8s_io_logs,
  ]
}

resource "aws_s3_bucket" "cdn_packages_k8s_io_replica" {
  provider = aws.us-east-1

  bucket = "${local.prefix}cdn-packages-k8s-io-replica"

  tags = local.tags
}

resource "aws_s3_bucket_versioning" "cdn_packages_k8s_io_replica" {
  provider = aws.us-east-1

  bucket = aws_s3_bucket.cdn_packages_k8s_io_replica.id

  versioning_configuration {
    status = "Enabled"
  }

  depends_on = [
    aws_s3_bucket.cdn_packages_k8s_io_replica,
  ]
}

resource "aws_s3_bucket_public_access_block" "cdn_packages_k8s_io_replica" {
  provider = aws.us-east-1

  bucket = aws_s3_bucket.cdn_packages_k8s_io_replica.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true

  depends_on = [
    aws_s3_bucket.cdn_packages_k8s_io_replica,
  ]
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cdn_packages_k8s_io_replica" {
  provider = aws.us-east-1

  bucket = aws_s3_bucket.cdn_packages_k8s_io_replica.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }

  depends_on = [
    aws_s3_bucket.cdn_packages_k8s_io_replica,
  ]
}

resource "aws_iam_role" "cdn_packages_k8s_io_replication" {
  name = "${local.prefix}cdn-packages-k8s-io-replication"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "s3.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = local.tags
}

resource "aws_iam_role_policy" "cdn_packages_k8s_io_replication" {
  name = "${local.prefix}cdn-packages-k8s-io-replication"
  role = aws_iam_role.cdn_packages_k8s_io_replication.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetReplicationConfiguration",
          "s3:ListBucket"
        ]
        Resource = aws_s3_bucket.cdn_packages_k8s_io.arn
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObjectVersionForReplication",
          "s3:GetObjectVersionAcl",
          "s3:GetObjectVersionTagging",
          "s3:GetObjectRetention",
          "s3:GetObjectLegalHold"
        ]
        Resource = "${aws_s3_bucket.cdn_packages_k8s_io.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ReplicateObject",
          "s3:ReplicateDelete",
          "s3:ReplicateTags"
        ]
        Resource = "${aws_s3_bucket.cdn_packages_k8s_io_replica.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = aws_kms_key.cdn_packages_k8s_io.arn
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Encrypt",
          "kms:GenerateDataKey"
        ]
        Resource = "arn:aws:kms:us-east-1:${local.account_id}:*"
      }
    ]
  })
}

resource "aws_s3_bucket_replication_configuration" "cdn_packages_k8s_io" {
  bucket = aws_s3_bucket.cdn_packages_k8s_io.id
  role   = aws_iam_role.cdn_packages_k8s_io_replication.arn

  rule {
    id       = "replicate-all"
    status   = "Enabled"
    priority = 0

    filter {
      prefix = ""
    }

    delete_marker_replication {
      status = "Disabled"
    }

    source_selection_criteria {
      sse_kms_encrypted_objects {
        status = "Enabled"
      }
    }

    destination {
      bucket        = aws_s3_bucket.cdn_packages_k8s_io_replica.arn
      storage_class = "STANDARD"

      encryption_configuration {
        replica_kms_key_id = "arn:aws:kms:us-east-1:${local.account_id}:alias/aws/s3"
      }
    }
  }

  depends_on = [
    aws_s3_bucket_versioning.cdn_packages_k8s_io,
    aws_s3_bucket_versioning.cdn_packages_k8s_io_replica,
    aws_iam_role_policy.cdn_packages_k8s_io_replication,
  ]
}

resource "aws_sns_topic" "cdn_packages_k8s_io" {
  name = "${local.prefix}cdn-packages-k8s-io-events"

  tags = local.tags
}

resource "aws_sns_topic_policy" "cdn_packages_k8s_io" {
  arn = aws_sns_topic.cdn_packages_k8s_io.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "AllowS3Publish"
      Effect = "Allow"
      Principal = {
        Service = "s3.amazonaws.com"
      }
      Action   = "SNS:Publish"
      Resource = aws_sns_topic.cdn_packages_k8s_io.arn
      Condition = {
        ArnLike = {
          "aws:SourceArn" = aws_s3_bucket.cdn_packages_k8s_io.arn
        }
        StringEquals = {
          "aws:SourceAccount" = local.account_id
        }
      }
    }]
  })
}

resource "aws_s3_bucket_notification" "cdn_packages_k8s_io" {
  bucket = aws_s3_bucket.cdn_packages_k8s_io.id

  topic {
    topic_arn = aws_sns_topic.cdn_packages_k8s_io.arn
    events = [
      "s3:ObjectCreated:*",
      "s3:ObjectRemoved:*"
    ]
  }

  depends_on = [
    aws_s3_bucket.cdn_packages_k8s_io,
    aws_sns_topic_policy.cdn_packages_k8s_io,
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
    aws_s3_bucket_public_access_block.cdn_packages_k8s_io,
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

resource "aws_cloudwatch_log_group" "cdn_packages_k8s_io" {
  provider = aws.us-east-1

  name              = "aws-waf-logs-${local.prefix}cdn-packages-k8s-io"
  retention_in_days = 90

  tags = local.tags
}

resource "aws_cloudwatch_log_resource_policy" "cdn_packages_k8s_io" {
  provider = aws.us-east-1

  policy_name = "${local.prefix}AWSWAFLogsPolicy-cdn-packages-k8s-io"

  policy_document = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "delivery.logs.amazonaws.com"
      }
      Action = [
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ]
      Resource = "${aws_cloudwatch_log_group.cdn_packages_k8s_io.arn}:*"
      Condition = {
        StringEquals = {
          "aws:SourceAccount" = local.account_id
        }
        ArnLike = {
          "aws:SourceArn" = "arn:aws:logs:us-east-1:${local.account_id}:*"
        }
      }
    }]
  })
}

resource "aws_wafv2_web_acl_logging_configuration" "cdn_packages_k8s_io" {
  provider = aws.us-east-1

  resource_arn            = aws_wafv2_web_acl.cdn_packages_k8s_io.arn
  log_destination_configs = [aws_cloudwatch_log_group.cdn_packages_k8s_io.arn]

  depends_on = [
    aws_cloudwatch_log_group.cdn_packages_k8s_io,
    aws_cloudwatch_log_resource_policy.cdn_packages_k8s_io,
  ]
}