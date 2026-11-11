```hcl
module "this" {
  source  = "cloudposse/label/null"
  version = "0.25.0"

  enabled             = var.enabled
  namespace           = var.namespace
  tenant              = var.tenant
  environment         = var.environment
  stage               = var.stage
  name                = var.name
  delimiter           = var.delimiter
  attributes          = var.attributes
  tags                = var.tags
  additional_tag_map  = var.additional_tag_map
  label_order         = var.label_order
  regex_replace_chars = var.regex_replace_chars
  id_length_limit     = var.id_length_limit
  label_key_case      = var.label_key_case
  label_value_case    = var.label_value_case
  descriptor_formats  = var.descriptor_formats
  labels_as_tags      = var.labels_as_tags

  context = var.context
}

locals {
  enabled = module.this.enabled

  aws_account_id = join("", data.aws_caller_identity.current.*.account_id)
  aws_partition  = join("", data.aws_partition.current.*.partition)

  datadog_aws_role_name = nonsensitive(join("", data.aws_ssm_parameter.datadog_aws_role_name.*.value))
  principal_names = [
    format("arn:${local.aws_partition}:iam::%s:role/${local.datadog_aws_role_name}", local.aws_account_id),
  ]

  privileged_principal_arns = [
    {
      (local.principal_names[0]) = [""]
    }
  ]

  data_current_order_body = one(data.http.current_order.*.response_body) == null? {} : jsondecode(data.http.current_order[0].response_body)
  current_order_data = lookup(local.data_current_order_body, "data", null)

  non_catchall_ids = local.enabled? [for x in local.current_order_data : x.id if x.attributes.name!= "catchall"] : []
  catchall_id      = local.enabled? [for x in local.current_order_data : x.id if x.attributes.name == "catchall"] : []
  ordered_ids      = concat(local.non_catchall_ids, local.catchall_id)

  policy = local.enabled? jsondecode(data.aws_iam_policy_document.default[0].json) : null
}

data "http" "current_order" {
  count = local.enabled? 1 : 0

  url        = format("https://api.%s/api/v2/logs/config/archives", module.datadog_configuration.datadog_site)
  depends_on = [datadog_logs_archive.logs_archive, datadog_logs_archive.catchall_archive]
  request_headers = {
    Accept             = "application/json",
    DD-API-KEY         = local.datadog_api_key,
    DD-APPLICATION-KEY = local.datadog_app_key
  }
}

data "aws_iam_policy_document" "default" {
  count = module.this.enabled? 1 : 0
  statement {
    sid = "AWSCloudTrailAclCheck"
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    actions = [
      "s3:GetBucketAcl",
    ]

    resources = [
      "arn:${local.aws_partition}:s3:::${module.this.id}-cloudtrail",
    ]
  }

  statement {
    sid = "AWSCloudTrailWrite1"
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    actions = [
      "s3:PutObject",
    ]

    resources = [
      "arn:${local.aws_partition}:s3:::${module.this.id}-cloudtrail/*",
    ]

    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values = [
        "bucket-owner-full-control",
      ]
    }
    condition {
      test     = "StringLike"
      variable = "aws:SourceArn"
      values = [
        "arn:${local.aws_partition}:cloudtrail:*:${local.aws_account_id}:trail/*datadog-logs-archive",
      ]
    }
  }

  statement {
    sid = "AWSCloudTrailWrite2"
    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }

    actions = [
      "s3:PutObject",
    ]

    resources = [
      "arn:${local.aws_partition}:s3:::${module.this.id}-cloudtrail/*",
    ]

    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values = [
        "bucket-owner-full-control",
      ]
    }
    condition {
      test     = "StringLike"
      variable = "aws:SourceArn"
      values = [
        "arn:${local.aws_partition}:cloudtrail:*:${local.aws_account_id}:trail/*datadog-logs-archive",
      ]
    }
  }
}

module "bucket_policy" {
  source  = "cloudposse/iam-policy/aws"
  version = "1.0.1"

  iam_policy_statements = try(lookup(local.policy, "Statement"), null)

  context = module.this.context
}

data "aws_ssm_parameter" "datadog_aws_role_name" {
  name = "/datadog/aws_role_name"
}

data "aws_caller_identity" "current" {
  count = local.enabled? 1 : 0
}

data "aws_partition" "current" {
  count = local.enabled? 1 : 0
}

module "archive_bucket" {
  source  = "cloudposse/s3-bucket/aws"
  version = "3.1.2"

  count = local.enabled? 1 : 0

  acl           = "private"
  enabled       = local.enabled
  force_destroy = var.s3_force_destroy

  lifecycle_rules = [
    {
      prefix  = null
      enabled = var.lifecycle_rules_enabled
      tags    = {}

      abort_incomplete_multipart_upload_days         = null
      enable_glacier_transition                      = var.enable_glacier_transition
      glacier_transition_days                        = var.glacier_transition_days
      noncurrent_version_glacier_transition_days     = 30
      enable_deeparchive_transition                  = false
      deeparchive_transition_days                    = 0
      noncurrent_version_deeparchive_transition_days = 0
      enable_standard_ia_transition                  = false
      standard_transition_days                       = 0
      enable_current_object_expiration               = false
      expiration_days                                = 0
      enable_noncurrent_version_expiration           = false
      noncurrent_version_expiration_days             = 0
    },
  ]

  privileged_principal_actions = [
    "s3:PutObject",
    "s3:GetObject",
    "s3:ListBucket",
  ]

  privileged_principal_arns = local.privileged_principal_arns

  tags = {
    managed-by = "terraform"
    env        = var.stage
    service    = "datadog-logs-archive"
    part-of    = "observability"
  }

  user_enabled       = false
  versioning_enabled = true

  object_lock_configuration = {
    mode  = var.object_lock_mode_archive
    days  = var.object_lock_days_archive
    years = null
  }

  context = module.this.context
}

module "cloudtrail_s3_bucket" {
  source  = "cloudposse/s3-bucket/aws"
  version = "3.1.2"

  depends_on = [data.aws_iam_policy_document.default]

  count = local.enabled? 1 : 0

  name          = "datadog-logs-archive-cloudtrail"
  acl           = "private"
  enabled       = local.enabled
  force_destroy = var.s3_force_destroy

  source_policy_documents = data.aws_iam_policy_document.default.*.json

  lifecycle_rules = [
    {
      prefix  = null
      enabled = var.lifecycle_rules_enabled
      tags    = {}

      abort_incomplete_multipart_upload_days         = null
      enable_glacier_transition                      = var.enable_glacier_transition
      glacier_transition_days                        = 365
      noncurrent_version_glacier_transition_days     = 365
      enable_deeparchive_transition                  = false
      deeparchive_transition_days                    = 0
      noncurrent_version_deeparchive_transition_days = 0
      enable_standard_ia_transition                  = false
      standard_transition_days                       = 0
      enable_current_object_expiration               = false
      expiration_days                                = 0
      enable_noncurrent_version_expiration           = false
      noncurrent_version_expiration_days             = 0
    },
  ]

  tags = {
    managed-by = "terraform"
    env        = var.stage
    service    = "datadog-logs-archive"
    part-of    = "observability"
  }

  user_enabled       = false
  versioning_enabled = true

  label_key_case   = "lower"
  label_value_case = "lower"

  object_lock_configuration = {
    mode  = var.object_lock_mode_cloudtrail
    days  = var.object_lock_days_cloudtrail
    years = null
  }

  allow_ssl_requests_only = false

  context = module.this.context
}

module "cloudtrail" {
  count = local.enabled? 1 : 0
  depends_on = [module.cloudtrail_s3_bucket]
  source     = "cloudposse/cloudtrail/aws"
  version    = "0.21.0"

  enable_log_file_validation    = true
  include_global_service_events = true
  is_multi_region_trail         = true
  enabled                       = local.enabled
  enable_logging                = true
  s3_bucket_name                = module.cloudtrail_s3_bucket[0].bucket_id
  s3_key_prefix                 = "cloudtrail"
  cloudwatch_logs_group_name    = "cloudtrail-logs"
  cloudwatch_logs_role_arn      = aws_iam_role.cloudtrail_cloudwatch_logs_role.arn
  kms_key_id                    = aws_kms_key.cloudtrail_kms_key.arn

  event_selector = [
    {
      include_management_events = true
      read_write_type           = "WriteOnly"
      data_resource = [
        {
          type   = "AWS::S3::Object"
          values = ["${module.archive_bucket[0].bucket_arn}/"]
        }
      ]
    }
  ]

  context = module.this.context
}

resource "aws_kms_key" "cloudtrail_kms_key" {
  count = local.enabled? 1 : 0
  description = "KMS key for CloudTrail logs"
  enable_key_rotation = true
}

resource "aws_iam_role" "cloudtrail_cloudwatch_logs_role" {
  count = local.enabled? 1 : 0
  name = "cloudtrail_cloudwatch_logs_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "cloudtrail_cloudwatch_logs_policy" {
  count = local.enabled? 1 : 0
  name = "cloudtrail_cloudwatch_logs_policy"
  role = aws_iam_role.cloudtrail_cloudwatch_logs_role[0].id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Effect = "Allow",
        Resource = "*"
      }
    ]
  })
}

resource "datadog_logs_archive_order" "archive_order" {
  count       = var.enabled? 1 : 0
  archive_ids = local.ordered_ids
}

resource "datadog_logs_archive" "logs_archive" {
  count = local.enabled? 1 : 0

  name             = var.stage
  include_tags     = true
  rehydration_tags = ["rehydrated:true"]
  query            = join(" OR ", concat([join(":", ["env", var.stage]), join(":", ["account", local.aws_account_id])], var.additional_query_tags))

  s3_archive {
    bucket     = module.archive_bucket[0].bucket_id
    path       = "/"
    account_id = local.aws_account_id
    role_name  = local.datadog_aws_role_name
  }
}

resource "datadog_logs_archive" "catchall_archive" {
  count = local.enabled && var.catchall_enabled? 1 : 0

  depends_on       = [datadog_logs_archive.logs_archive]
  name             = "catchall"
  include_tags     = true
  rehydration_tags = ["rehydrated:true"]
  query            = "*"

  s3_archive {
    bucket     = module.archive_bucket[0].bucket_id
    path       = "/catchall"
    account_id = local.aws_account_id
    role_name  = local.datadog_aws_role_name
  }
}

output "bucket_arn" {
  value       = local.enabled? module.archive_bucket[0].bucket_arn : ""
  description = "The ARN of the bucket used for log archive storage"
}

output "bucket_domain_name" {
  value       = local.enabled? module.archive_bucket[0].bucket_domain_name : ""
  description = "The FQDN of the bucket used for log archive storage"
}

output "bucket_id" {
  value       = local.enabled? module.archive_bucket[0].bucket_id : ""
  description = "The ID (name) of the bucket used for log archive storage"
}

output "bucket_region" {
  value       = local.enabled? module.archive_bucket[0].bucket_region : ""
  description = "The region of the bucket used for log archive storage"
}

output "cloudtrail_bucket_arn" {
  value       = local.enabled? module.cloudtrail_s3_bucket[0].bucket_arn : ""
  description = "The ARN of the bucket used for access logging via cloudtrail"
}

output "cloudtrail_bucket_domain_name" {
  value       = local.enabled? module.cloudtrail_s3_bucket[0].bucket_domain_name : ""
  description = "The FQDN of the bucket used for access logging via cloudtrail"
}

output "cloudtrail_bucket_id" {
  value       = local.enabled? module.cloudtrail_s3_bucket[0].bucket_id : ""
  description = "The ID (name) of the bucket used for access logging via cloudtrail"
}

output "archive_id" {
  value       = local.enabled? datadog_logs_archive.logs_archive[0].id : ""
  description = "The ID of the environment-specific log archive"
}

output "catchall_id" {
  value       = local.enabled && var.catchall_enabled? datadog_logs_archive.catchall_archive[0].id : ""
  description = "The ID of the catchall log archive"
}

module "datadog_configuration" {
  source  = "../datadog-configuration/modules/datadog_keys"
  enabled = true
  context = module.this.context
}

locals {
  datadog_api_key = module.datadog_configuration.datadog_api_key
  datadog_app_key = module.datadog_configuration.datadog_app_key
}

provider "datadog" {
  api_key  = local.datadog_api_key
  app_key  = local.datadog_app_key
  api_url  = module.datadog_configuration.datadog_api_url
  validate = local.enabled
}

provider "aws" {
  region = var.region

  profile = module.iam_roles.terraform_profile_name

  dynamic "assume_role" {
    for_each = compact([module.iam_roles.terraform_role_arn])
    content {
      role_arn = assume_role.value
    }
  }
}

module "iam_roles" {
  source  = "../account-map/modules/iam-roles"
  context = module.this.context
}

variable "region" {
  type        = string
  description = "AWS Region"
}

variable "additional_query_tags" {
  type        = list(any)
  description = "Additional tags to be used in the query for this archive"
  default     = []
}

variable "catchall_enabled" {
  type        = bool
  description = "Set to true to enable a catchall for logs unmatched by any queries. This should only be used in one environment/account"
  default     = false
}

variable "lifecycle_rules_enabled" {
  type        = bool
  description = "Enable/disable lifecycle management rules for log archive s3 objects"
  default     = true
}

variable "enable_glacier_transition" {
  type        = bool
  description = "Enable/disable transition to glacier for log archive bucket. Has no effect unless lifecycle_rules_enabled set to true"
  default     = true
}

variable "glacier_transition_days" {
  type        = number
  description = "Number of days after which to transition objects to glacier storage in log archive bucket"
  default     = 365
}

variable "object_lock_days_archive" {
  type        = number
  description = "Object lock duration for archive buckets in days"
  default     = 7
}

variable "object_lock_days_cloudtrail" {
  type        = number
  description = "Object lock duration for cloudtrail buckets in days"
  default     = 7
}

variable "object_lock_mode_archive" {
  type        = string
  description = "Object lock mode for archive bucket. Possible values are COMPLIANCE or GOVERNANCE"
  default     = "COMPLIANCE"
}

variable "object_lock_mode_cloudtrail" {
  type        = string
  description = "Object lock mode for cloudtrail bucket. Possible values are COMPLIANCE or GOVERNANCE"
  default     = "COMPLIANCE"
}

variable "s3_force_destroy" {
  type        = bool
  description = "Set to true to delete non-empty buckets when enabled is set to false"
  default     = false
}

terraform {
  required_version = ">= 0.13.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 4.9.0"
    }
    datadog = {
      source  = "datadog/datadog"
      version = ">= 3.19"
    }
    http = {
      source  = "hashicorp/http"
      version = ">= 2.1.0"
    }
  }
}