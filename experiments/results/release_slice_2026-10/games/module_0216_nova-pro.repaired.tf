resource "aws_cloudfront_cache_policy" "no_cookies" {
  provider = aws.networking
  name     = "no-cookies"

  min_ttl     = 0
  default_ttl = 86400
  max_ttl     = 31536000

  parameters_in_cache_key_and_forwarded_to_origin {
    cookies_config {
      cookie_behavior = "none"
    }

    headers_config {
      header_behavior = "whitelist"
      headers {
        items = ["Origin"]
      }
    }

    query_strings_config {
      query_string_behavior = "all"
    }
  }
}

resource "aws_cloudfront_distribution" "cloudfront_distribution" {
  provider = aws.networking

  enabled         = true
  is_ipv6_enabled = true

  origin_group {
    origin_id = "registry-k8s-io-prod-image-layers"

    failover_criteria {
      status_codes = [403, 404, 500, 502]
    }

    member {
      origin_id = "registry-k8s-io-prod-us-east-2"
    }

    member {
      origin_id = "registry-k8s-io-prod-eu-west-1"
    }
  }

  origin {
    domain_name = "prod-registry-k8s-io-us-east-2.s3.us-east-2.amazonaws.com"
    origin_id   = "registry-k8s-io-prod-us-east-2"

    origin_shield {
      enabled              = true
      origin_shield_region = "us-east-2"
    }
  }

  origin {
    domain_name = "prod-registry-k8s-io-eu-west-1.s3.eu-west-1.amazonaws.com"
    origin_id   = "registry-k8s-io-prod-eu-west-1"

    origin_shield {
      enabled              = true
      origin_shield_region = "eu-west-1"
    }
  }

  default_cache_behavior {
    allowed_methods = ["GET", "HEAD"]
    cached_methods  = ["GET", "HEAD"]

    target_origin_id = "registry-k8s-io-prod-image-layers"

    cache_policy_id = aws_cloudfront_cache_policy.no_cookies.id

    viewer_protocol_policy = "redirect-to-https"
  }

  price_class = "PriceClass_100"

  restrictions {
    geo_restriction {
      restriction_type = "whitelist"
      locations        = ["US"]
    }
  }

  default_root_object = "index.html"

  viewer_certificate {
    cloudfront_default_certificate = true
    minimum_protocol_version = "TLSv1.2_2021"
  }

  web_acl_id = aws_wafv2_web_acl.cloudfront_waf.arn

  tags = var.tags
}

resource "aws_wafv2_web_acl" "cloudfront_waf" {
  name        = "cloudfront-waf"
  scope       = "CLOUDFRONT"
  description = "WAF for CloudFront distribution"

  default_action {
    allow {}
  }

  rule {
    name = "log4j-rule"
    priority = 1
    action {
      allow {}
    }
    statement {
      managed_rule_group {
        name    = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "cloudfront-waf-metrics"
    sampled_requests_enabled   = true
  }
}

resource "aws_cloudfront_monitoring_subscription" "cloudfront" {
  provider = aws.networking

  distribution_id = aws_cloudfront_distribution.cloudfront_distribution.id

  monitoring_subscription {
    realtime_metrics_subscription_config {
      realtime_metrics_subscription_status = "Enabled"
    }
  }
}

data "aws_organizations_organization" "current" {}

data "aws_iam_policy_document" "s3_assume_role" {
  statement {
    effect = "Allow"
    principals {
      type = "Service"
      identifiers = [
        "s3.amazonaws.com",
        "batchoperations.s3.amazonaws.com",
      ]
    }
    actions = ["sts:AssumeRole"]
  }
}

data "aws_iam_policy_document" "replication" {
  policy_id = "CrossRegionReplicationPolicy"
  statement {
    effect = "Allow"
    actions = [
      "s3:GetReplicationConfiguration",
      "s3:GetObjectVersionForReplication",
      "s3:GetObjectVersionAcl",
      "s3:GetObjectVersionTagging",
      "s3:ListBucket",
    ]
    resources = ["arn:aws:s3:::prod-registry-k8s-io-us-east-2", "arn:aws:s3:::prod-registry-k8s-io-eu-west-1"]
  }

  statement {
    effect = "Allow"
    actions = [
      "s3:ReplicateObject",
      "s3:ReplicateDelete",
      "s3:ReplicateTags",
    ]
    resources = ["arn:aws:s3:::prod-registry-k8s-io-us-east-2/*", "arn:aws:s3:::prod-registry-k8s-io-eu-west-1/*"]
  }
}

resource "aws_iam_role" "replication" {
  provider = aws.registry-k8s-io-prod

  name_prefix        = "registry-k8s-io-s3-replication"
  path               = "/"
  assume_role_policy = data.aws_iam_policy_document.s3_assume_role.json
  inline_policy {
    name   = "S3Replication"
    policy = data.aws_iam_policy_document.replication.json
  }
}

locals {
  assume_role_arn = "arn:aws:iam::${local.registry_k8s_io_prod_account_id}:role/OrganizationAccountAccessRole"

  audit-account-name  = "k8s-infra-security-audit"
  audit-account-index = index(data.aws_organizations_organization.current.accounts.*.name, local.audit-account-name)
  audit-account-id    = data.aws_organizations_organization.current.accounts[local.audit-account-index].id

  logging-account-name  = "k8s-infra-security-logs"
  logging-account-index = index(data.aws_organizations_organization.current.accounts.*.name, local.logging-account-name)
  logging-account-id    = data.aws_organizations_organization.current.accounts[local.logging-account-index].id

  networking-account-name  = "k8s-infra-networking"
  networking-account-index = index(data.aws_organizations_organization.current.accounts.*.name, local.networking-account-name)
  networking-account-id    = data.aws_organizations_organization.current.accounts[local.networking-account-index].id

  registry-k8s-io-prod-name       = "k8s-infra-registry-k8s-io-prod"
  registry_k8s_io_prod_ci_index   = index(data.aws_organizations_organization.current.accounts[*].name, local.registry-k8s-io-prod-name)
  registry_k8s_io_prod_account_id = data.aws_organizations_organization.current.accounts[local.registry_k8s_io_prod_ci_index].id
}

output "cloudfront_domain_name" {
  value = aws_cloudfront_distribution.cloudfront_distribution.domain_name
}

terraform {
  backend "s3" {
    bucket = "k8s-infra-registry-k8s-io-tf-state"
    key    = "prod/terraform.tfstate"
    region = "us-east-2"
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.33.0"
    }
  }
}

provider "aws" {
  region = "us-east-2"
  alias  = "networking"

  assume_role {
    role_arn = "arn:aws:iam::${local.networking-account-id}:role/OrganizationAccountAccessRole"
  }
}

provider "aws" {
  region = "us-east-2"
}

provider "aws" {
  alias  = "registry-k8s-io-prod"
  region = "us-east-2"

  assume_role {
    role_arn = local.assume_role_arn
  }
}

provider "aws" {
  alias  = "ca-central-1"
  region = "ca-central-1"

  assume_role {
    role_arn = local.assume_role_arn
  }
}

provider "aws" {
  alias  = "us-east-1"
  region = "us-east-1"

  assume_role {
    role_arn = local.assume_role_arn
  }
}

provider "aws" {
  alias  = "us-east-2"
  region = "us-east-2"

  assume_role {
    role_arn = local.assume_role_arn
  }
}

provider "aws" {
  alias  = "us-west-1"
  region = "us-west-1"

  assume_role {
    role_arn = local.assume_role_arn
  }
}

provider "aws" {
  alias  = "us-west-2"
  region = "us-west-2"

  assume_role {
    role_arn = local.assume_role_arn
  }
}

module "ca_central_1" {
  providers = {
    aws = aws.ca-central-1
  }

  source = "../modules/registry-k8s-io-s3-bucket"
}

module "us_east_1" {
  providers = {
    aws = aws.us-east-1
  }

  source = "../modules/registry-k8s-io-s3-bucket"
}

module "us_east_2" {
  providers = {
    aws = aws.us-east-2
  }

  source = "../modules/registry-k8s-io-s3-bucket"
}

module "us_west_1" {
  providers = {
    aws = aws.us-west-1
  }

  source = "../modules/registry-k8s-io-s3-bucket"
}

module "us_west_2" {
  providers = {
    aws = aws.us-west-2
  }

  source = "../modules/registry-k8s-io-s3-bucket"
}

variable "tags" {
  type = map(string)
  default = {
    "managed-by" = "Terraform",
    "group"      = "sig-k8s-infra",
    "subproject" = "registry.k8s.io"
    "githubRepo" = "git.k8s.io/k8s.io"
  }
}

terraform {
  required_version = "~> 1.1"
}