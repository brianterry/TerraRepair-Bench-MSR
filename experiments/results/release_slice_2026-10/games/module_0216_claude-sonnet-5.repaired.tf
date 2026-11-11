/*
Copyright 2024 The Kubernetes Authors.

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

resource "aws_cloudfront_cache_policy" "no_cookies" {
  provider = aws.networking
  name     = "no-cookies"

  min_ttl     = 0
  default_ttl = 86400
  max_ttl     = 31536000 // 1 year

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

resource "aws_s3_bucket" "cloudfront_logs" {
  provider = aws.networking
  bucket   = "registry-k8s-io-cloudfront-logs"
}

resource "aws_cloudfront_response_headers_policy" "security_headers" {
  provider = aws.networking
  name     = "registry-k8s-io-security-headers"

  security_headers_config {
    content_type_options {
      override = true
    }

    frame_options {
      frame_option = "DENY"
      override     = true
    }

    referrer_policy {
      referrer_policy = "strict-origin-when-cross-origin"
      override        = true
    }

    strict_transport_security {
      access_control_max_age_sec = 63072000
      include_subdomains         = true
      preload                    = true
      override                   = true
    }

    xss_protection {
      mode_block = true
      protection = true
      override   = true
    }
  }
}

resource "aws_wafv2_web_acl" "cloudfront_waf" {
  provider = aws.networking_us_east_1
  name     = "registry-k8s-io-cloudfront-waf"
  scope    = "CLOUDFRONT"

  default_action {
    allow {}
  }

  rule {
    name     = "AWS-AWSManagedRulesKnownBadInputsRuleSet"
    priority = 0

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
    metric_name                = "registry-k8s-io-cloudfront-waf"
    sampled_requests_enabled   = true
  }

  tags = var.tags
}

resource "aws_cloudfront_distribution" "cloudfront_distribution" {
  provider = aws.networking

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  web_acl_id          = aws_wafv2_web_acl.cloudfront_waf.arn

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

    cache_policy_id            = aws_cloudfront_cache_policy.no_cookies.id
    response_headers_policy_id = aws_cloudfront_response_headers_policy.security_headers.id

    viewer_protocol_policy = "redirect-to-https"
  }

  price_class = "PriceClass_100"

  restrictions {
    geo_restriction {
      restriction_type = "blacklist"
      locations        = []
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
    minimum_protocol_version       = "TLSv1.2_2021"
  }

  logging_config {
    include_cookies = false
    bucket          = aws_s3_bucket.cloudfront_logs.bucket_domain_name
    prefix          = "cloudfront/"
  }

  tags = var.tags
}

# Enable real-time monitoring on cloud distribution
resource "aws_cloudfront_monitoring_subscription" "cloudfront" {
  provider = aws.networking

  distribution_id = aws_cloudfront_distribution.cloudfront_distribution.id

  monitoring_subscription {
    realtime_metrics_subscription_config {
      realtime_metrics_subscription_status = "Enabled"
    }
  }
}


/*
Copyright 2024 The Kubernetes Authors.

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

data "aws_organizations_organization" "current" {}


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

###
# Replication
###

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
    actions = [
      "s3:GetReplicationConfiguration",
      "s3:GetObjectVersionForReplication",
      "s3:GetObjectVersionAcl",
      "s3:GetObjectVersionTagging",
      "s3:ListBucket",
    ]

    resources = ["arn:aws:s3:::prod-registry-k8s-io-*"]
  }

  statement {
    actions = [
      "s3:ReplicateObject",
      "s3:ReplicateDelete",
      "s3:ReplicateTags",
    ]

    resources = ["arn:aws:s3:::prod-registry-k8s-io-*/*"]
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


/*
Copyright 2024 The Kubernetes Authors.

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

output "cloudfront_domain_name" {
  value = aws_cloudfront_distribution.cloudfront_distribution.domain_name
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
  region = "us-east-1"
  alias  = "networking_us_east_1"

  assume_role {
    role_arn = "arn:aws:iam::${local.networking-account-id}:role/OrganizationAccountAccessRole"
  }
}

# Provider for AWS non-region-specific operations
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


/*
Copyright 2024 The Kubernetes Authors.

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


variable "tags" {
  type = map(string)
  default = {
    "managed-by" = "Terraform",
    "group"      = "sig-k8s-infra",
    "subproject" = "registry.k8s.io"
    "githubRepo" = "git.k8s.io/k8s.io"
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

terraform {
  required_version = "~> 1.1"
}