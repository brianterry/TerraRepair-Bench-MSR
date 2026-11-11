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

variable "context" {
  type = any
  default = {
    enabled             = true
    namespace           = null
    tenant              = null
    environment         = null
    stage               = null
    name                = null
    delimiter           = null
    attributes          = []
    tags                = {}
    additional_tag_map  = {}
    regex_replace_chars = null
    label_order         = []
    id_length_limit     = null
    label_key_case      = null
    label_value_case    = null
    descriptor_formats  = {}
    labels_as_tags = ["unset"]
  }
  description = <<-EOT
    Single object for setting entire context at once.
    See description of individual variables for details.
    Leave string and numeric variables as `null` to use default value.
    Individual variable settings (non-null) override settings in context object,
    except for attributes, tags, and additional_tag_map, which are merged.
  EOT

  validation {
    condition     = lookup(var.context, "label_key_case", null) == null ? true : contains(["lower", "title", "upper"], var.context["label_key_case"])
    error_message = "Allowed values: `lower`, `title`, `upper`."
  }

  validation {
    condition     = lookup(var.context, "label_value_case", null) == null ? true : contains(["lower", "title", "upper", "none"], var.context["label_value_case"])
    error_message = "Allowed values: `lower`, `title`, `upper`, `none`."
  }
}

variable "enabled" {
  type        = bool
  default     = null
  description = "Set to false to prevent the module from creating any resources"
}

variable "namespace" {
  type        = string
  default     = null
  description = "ID element. Usually an abbreviation of your organization name, e.g. 'eg' or 'cp', to help ensure generated IDs are globally unique"
}

variable "tenant" {
  type        = string
  default     = null
  description = "ID element _(Rarely used, not included by default)_. A customer identifier, indicating who this instance of a resource is for"
}

variable "environment" {
  type        = string
  default     = null
  description = "ID element. Usually used for region e.g. 'uw2', 'us-west-2', OR role 'prod', 'staging', 'dev', 'UAT'"
}

variable "stage" {
  type        = string
  default     = null
  description = "ID element. Usually used to indicate role, e.g. 'prod', 'staging', 'source', 'build', 'test', 'deploy', 'release'"
}

variable "name" {
  type        = string
  default     = null
  description = <<-EOT
    ID element. Usually the component or solution name, e.g. 'app' or 'jenkins'.
    This is the only ID element not also included as a `tag`.
    The "name" tag is set to the full `id` string. There is no tag with the value of the `name` input.
    EOT
}

variable "delimiter" {
  type        = string
  default     = null
  description = <<-EOT
    Delimiter to be used between ID elements.
    Defaults to `-` (hyphen). Set to `""` to use no delimiter at all.
  EOT
}

variable "attributes" {
  type        = list(string)
  default     = []
  description = <<-EOT
    ID element. Additional attributes (e.g. `workers` or `cluster`) to add to `id`,
    in the order they appear in the list. New attributes are appended to the
    end of the list. The elements of the list are joined by the `delimiter`
    and treated as a single ID element.
    EOT
}

variable "labels_as_tags" {
  type        = set(string)
  default     = ["default"]
  description = <<-EOT
    Set of labels (ID elements) to include as tags in the `tags` output.
    Default is to include all labels.
    Tags with empty values will not be included in the `tags` output.
    Set to `[]` to suppress all generated tags.
    **Notes:**
      The value of the `name` tag, if included, will be the `id`, not the `name`.
      Unlike other `null-label` inputs, the initial setting of `labels_as_tags` cannot be
      changed in later chained modules. Attempts to change it will be silently ignored.
    EOT
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = <<-EOT
    Additional tags (e.g. `{'BusinessUnit': 'XYZ'}`).
    Neither the tag keys nor the tag values will be modified by this module.
    EOT
}

variable "additional_tag_map" {
  type        = map(string)
  default     = {}
  description = <<-EOT
    Additional key-value pairs to add to each map in `tags_as_list_of_maps`. Not added to `tags` or `id`.
    This is for some rare cases where resources want additional configuration of tags
    and therefore take a list of maps with tag key, value, and additional configuration.
    EOT
}

variable "label_order" {
  type        = list(string)
  default     = null
  description = <<-EOT
    The order in which the labels (ID elements) appear in the `id`.
    Defaults to ["namespace", "environment", "stage", "name", "attributes"].
    You can omit any of the 6 labels ("tenant" is the 6th), but at least one must be present.
    EOT
}

variable "regex_replace_chars" {
  type        = string
  default     = null
  description = <<-EOT
    Terraform regular expression (regex) string.
    Characters matching the regex will be removed from the ID elements.
    If not set, `"/[^a-zA-Z0-9-]/"` is used to remove all characters other than hyphens, letters and digits.
  EOT
}

variable "id_length_limit" {
  type        = number
  default     = null
  description = <<-EOT
    Limit `id` to this many characters (minimum 6).
    Set to `0` for unlimited length.
    Set to `null` for keep the existing setting, which defaults to `0`.
    Does not affect `id_full`.
  EOT
  validation {
    condition     = var.id_length_limit == null ? true : var.id_length_limit >= 6 || var.id_length_limit == 0
    error_message = "The id_length_limit must be >= 6 if supplied (not null), or 0 for unlimited length."
  }
}

variable "label_key_case" {
  type        = string
  default     = null
  description = <<-EOT
    Controls the letter case of the `tags` keys (label names) for tags generated by this module.
    Does not affect keys of tags passed in via the `tags` input.
    Possible values: `lower`, `title`, `upper`.
    Default value: `title`.
  EOT

  validation {
    condition     = var.label_key_case == null ? true : contains(["lower", "title", "upper"], var.label_key_case)
    error_message = "Allowed values: `lower`, `title`, `upper`."
  }
}

variable "label_value_case" {
  type        = string
  default     = null
  description = <<-EOT
    Controls the letter case of ID elements (labels) as included in `id`,
    set as tag values, and output by this module individually.
    Does not affect values of tags passed in via the `tags` input.
    Possible values: `lower`, `title`, `upper` and `none` (no transformation).
    Set this to `title` and set `delimiter` to `""` to yield Pascal Case IDs.
    Default value: `lower`.
  EOT

  validation {
    condition     = var.label_value_case == null ? true : contains(["lower", "title", "upper", "none"], var.label_value_case)
    error_message = "Allowed values: `lower`, `title`, `upper`, `none`."
  }
}

variable "descriptor_formats" {
  type        = any
  default     = {}
  description = <<-EOT
    Describe additional descriptors to be output in the `descriptors` output map.
    Map of maps. Keys are names of descriptors. Values are maps of the form
    `{
       format = string
       labels = list(string)
    }`
    (Type is `any` so the map values can later be enhanced to provide additional options.)
    `format` is a Terraform format string to be passed to the `format()` function.
    `labels` is a list of labels, in order, to pass to `format()` function.
    Label values will be normalized before being passed to `format()` so they will be
    identical to how they appear in `id`.
    Default is `{}` (`descriptors` output will be empty).
    EOT
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

  data_current_order_body = one(data.http.current_order.*.response_body) == null ? {} : jsondecode(data.http.current_order[0].response_body)
  current_order_data = lookup(local.data_current_order_body, "data", null)

  non_catchall_ids = local.enabled ? [for x in local.current_order_data : x.id if x.attributes.name != "catchall"] : []
  catchall_id      = local.enabled ? [for x in local.current_order_data : x.id if x.attributes.name == "catchall"] : []
  ordered_ids      = concat(local.non_catchall_ids, local.catchall_id)

  policy = local.enabled ? jsondecode(data.aws_iam_policy_document.default[0].json) : null
}

data "http" "current_order" {
  count = local.enabled ? 1 : 0

  url        = format("https://api.%s/api/v2/logs/config/archives", module.datadog_configuration.datadog_site)
  depends_on = [datadog_logs_archive.logs_archive, datadog_logs_archive.catchall_archive]
  request_headers = {
    Accept             = "application/json",
    DD-API-KEY         = local.datadog_api_key,
    DD-APPLICATION-KEY = local.datadog_app_key
  }
}

data "aws_iam_policy_document" "default" {
  count = module.this.enabled ? 1 : 0
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
  count = local.enabled ? 1 : 0
}

data "aws_partition" "current" {
  count = local.enabled ? 1 : 0
}

module "archive_bucket" {
  source  = "cloudposse/s3-bucket/aws"
  version = "3.1.2"

  count = local.enabled ? 1 : 0

  acl           = "private"
  enabled       = local.enabled
  force_destroy = var.s3_force_destroy

  logging = {
    bucket_name = module.archive_bucket[0].bucket_id
    prefix      = "logs/"
  }

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

  kms_master_key_arn = aws_kms_key.archive_bucket_key.arn
  sse_algorithm      = "aws:kms"

  object_lock_configuration = {
    mode  = var.object_lock_mode_archive
    days  = var.object_lock_days_archive
    years = null
  }

  context = module.this.context
}

resource "aws_kms_key" "archive_bucket_key" {
  count = local.enabled ? 1 : 0

  description             = "KMS key for encrypting archive bucket"
  enable_key_rotation     = true
  deletion_window_in_days = 7
}

module "cloudtrail_s3_bucket" {
  source  = "cloudposse/s3-bucket/aws"
  version = "3.1.2"

  depends_on = [data.aws_iam_policy_document.default]

  count = local.enabled ? 1 : 0

  name          = "datadog-logs-archive-cloudtrail"
  acl           = "private"
  enabled       = local.enabled
  force_destroy = var.s3_force_destroy

  source_policy_documents = data.aws_iam_policy_document.default.*.json

  logging = {
    bucket_name = module.cloudtrail_s3_bucket[0].bucket_id
    prefix      = "logs/"
  }

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

  kms_master_key_arn = aws_kms_key.cloudtrail_bucket_key.arn
  sse_algorithm      = "aws:kms"

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

resource "aws_kms_key" "cloudtrail_bucket_key" {
  count = local.enabled ? 1 : 0

  description             = "KMS key for encrypting cloudtrail bucket"
  enable_key_rotation     = true
  deletion_window_in_days = 7
}

module "cloudtrail" {
  count = local.enabled ? 1 : 0
  depends_on = [module.cloudtrail_s3_bucket]
  source     = "cloudposse/cloudtrail/aws"
  version    = "0.21.0"

  enable_log_file_validation    = true
  include_global_service_events = true
  is_multi_region_trail         = true
  enabled                       = local.enabled
  enable_logging                = true
  s3_bucket_name                = module.cloudtrail_s3_bucket[0].bucket_id
  cloud_watch_logs_group_arn    = aws_cloudwatch_log_group.cloudtrail_logs.arn
  cloud_watch_logs_role_arn     = aws_iam_role.cloudtrail_to_cloudwatch.arn
  kms_key_id                    = aws_kms_key.cloudtrail_key.arn

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

resource "aws_kms_key" "cloudtrail_key" {
  count = local.enabled ? 1 : 0

  description             = "KMS key for encrypting CloudTrail logs"
  enable_key_rotation     = true
  deletion_window_in_days = 7
}

resource "aws_cloudwatch_log_group" "cloudtrail_logs" {
  count = local.enabled ? 1 : 0

  name = "cloudtrail-logs"
}

resource "aws_iam_role" "cloudtrail_to_cloudwatch" {
  count = local.enabled ? 1 : 0

  name = "cloudtrail_to_cloudwatch_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "cloudtrail_to_cloudwatch_policy" {
  count = local.enabled ? 1 : 0

  name = "cloudtrail_to_cloudwatch_policy"
  role = aws_iam_role.cloudtrail_to_cloudwatch[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Effect   = "Allow"
        Resource = aws_cloudwatch_log_group.cloudtrail_logs[0].arn
      }
    ]
  })
}

resource "datadog_logs_archive_order" "archive_order" {
  count       = var.enabled ? 1 : 0
  archive_ids = local.ordered_ids
}

resource "datadog_logs_archive" "logs_archive" {
  count = local.enabled ? 1 : 0

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
  count = local.enabled && var.catchall_enabled ? 1 : 0

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
  value       = local.enabled ? module.archive_bucket[0].bucket_arn : ""
  description = "The ARN of the bucket used for log archive storage"
}

output "bucket_domain_name" {
  value       = local.enabled ? module.archive_bucket[0].bucket_domain_name : ""
  description = "The FQDN of the bucket used for log archive storage"
}

output "bucket_id" {
  value       = local.enabled ? module.archive_bucket[0].bucket_id : ""
  description = "The ID (name) of the bucket used for log archive storage"
}

output "bucket_region" {
  value       = local.enabled ? module.archive_bucket[0].bucket_region : ""
  description = "The region of the bucket used for log archive storage"
}

output "cloudtrail_bucket_arn" {
  value       = local.enabled ? module.cloudtrail_s3_bucket[0].bucket_arn : ""
  description = "The ARN of the bucket used for access logging via cloudtrail"
}

output "cloudtrail_bucket_domain_name" {
  value       = local.enabled ? module.cloudtrail_s3_bucket[0].bucket_domain_name : ""
  description = "The FQDN of the bucket used for access logging via cloudtrail"
}

output "cloudtrail_bucket_id" {
  value       = local.enabled ? module.cloudtrail_s3_bucket[0].bucket_id : ""
  description = "The ID (name) of the bucket used for access logging via cloudtrail"
}

output "archive_id" {
  value       = local.enabled ? datadog_logs_archive.logs_archive[0].id : ""
  description = "The ID of the environment-specific log archive"
}

output "catchall_id" {
  value       = local.enabled && var.catchall_enabled ? datadog_logs_archive.catchall_archive[0].id : ""
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