data "aws_iam_policy_document" "cloudtrail_cloudwatch_logs_assume_role" {
  count = local.enabled ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "cloudtrail_cloudwatch_logs" {
  count = local.enabled ? 1 : 0

  statement {
    actions = [
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams"
    ]

    resources = [
      join("", aws_cloudwatch_log_group.cloudtrail_cloudwatch_logs[*].arn)
    ]
  }

  statement {
    actions = [
      "logs:PutLogEvents",
      "logs:CreateLogStream"
    ]

    resources = [
      "${join("", aws_cloudwatch_log_group.cloudtrail_cloudwatch_logs[*].arn)}:*"
    ]
  }
}

resource "aws_iam_role" "cloudtrail_cloudwatch_logs" {
  count                = local.enabled ? 1 : 0
  name                 = module.this.id
  assume_role_policy   = join("", data.aws_iam_policy_document.cloudtrail_cloudwatch_logs_assume_role[*].json)
  description          = "Allow CloudTrail to write to CloudWatch Logs"
  max_session_duration = var.cloudtrail_cloudwatch_logs_role_max_session_duration
  tags                 = module.this.tags
}

resource "aws_iam_policy" "cloudtrail_cloudwatch_logs" {
  count       = local.enabled ? 1 : 0
  name        = module.this.id
  description = "Allow CloudTrail to write to CloudWatch Logs"
  policy      = join("", data.aws_iam_policy_document.cloudtrail_cloudwatch_logs[*].json)
  tags        = module.this.tags
}

resource "aws_iam_role_policy_attachment" "cloudtrail_cloudwatch_logs" {
  count      = local.enabled ? 1 : 0
  role       = join("", aws_iam_role.cloudtrail_cloudwatch_logs[*].name)
  policy_arn = join("", aws_iam_policy.cloudtrail_cloudwatch_logs[*].arn)
}

resource "aws_cloudwatch_log_group" "cloudtrail_cloudwatch_logs" {
  count             = local.enabled ? 1 : 0
  name              = module.this.id
  retention_in_days = var.cloudwatch_logs_retention_in_days
  kms_key_id        = module.kms_key_cloudtrail.key_arn
  tags              = module.this.tags
}


locals {
  audit_access_enabled = module.this.enabled && var.audit_access_enabled
  audit_account_id     = module.account_map.outputs.full_account_map[module.account_map.outputs.audit_account_account_name]
}

module "kms_key_cloudtrail" {
  source = "github.com/cloudposse/terraform-aws-kms-key.git?ref=0.12.1"

  description             = "KMS key for CloudTrail"
  deletion_window_in_days = 10
  enable_key_rotation     = true
  policy                  = join("", data.aws_iam_policy_document.kms_key_cloudtrail[*].json)

  context = module.this.context
}

data "aws_caller_identity" "this" {
  count = local.enabled ? 1 : 0
}

data "aws_partition" "current" {
  count = local.enabled ? 1 : 0
}

data "aws_iam_policy_document" "kms_key_cloudtrail" {
  count = local.enabled ? 1 : 0

  statement {
    sid    = "Allow the account identity to manage the KMS key"
    effect = "Allow"

    actions = [
      "kms:*"
    ]

    resources = [
      format("arn:%s:kms:*:%s:key/*", join("", data.aws_partition.current[*].partition), join("", data.aws_caller_identity.this[*].account_id))
    ]

    principals {
      type = "AWS"

      identifiers = [
        format("arn:${join("", data.aws_partition.current[*].partition)}:iam::%s:root", join("", data.aws_caller_identity.this[*].account_id))
      ]
    }
  }

  statement {
    sid    = "Allow CloudTrail to encrypt with the KMS key"
    effect = "Allow"

    actions = [
      "kms:Encrypt",
      "kms:GenerateDataKey*"
    ]

    resources = [
      format("arn:%s:kms:*:%s:key/*", join("", data.aws_partition.current[*].partition), join("", data.aws_caller_identity.this[*].account_id))
    ]

    principals {
      type = "Service"

      identifiers = [
        "cloudtrail.amazonaws.com"
      ]
    }

    condition {
      test     = "StringLike"
      variable = "kms:EncryptionContext:aws:cloudtrail:arn"

      values = [
        format("arn:${join("", data.aws_partition.current[*].partition)}:cloudtrail:*:%s:trail/*", join("", data.aws_caller_identity.this[*].account_id))
      ]
    }
  }

  statement {
    sid    = "Allow CloudWatch Logs to use the KMS key"
    effect = "Allow"

    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:Describe*"
    ]

    resources = [
      format("arn:%s:kms:*:%s:key/*", join("", data.aws_partition.current[*].partition), join("", data.aws_caller_identity.this[*].account_id))
    ]

    principals {
      type = "Service"

      identifiers = [
        "logs.amazonaws.com"
      ]
    }
  }

  dynamic "statement" {
    for_each = local.audit_access_enabled ? [1] : []
    content {
      sid    = "Allow Audit to decrypt with the KMS key"
      effect = "Allow"
      actions = [
        "kms:Decrypt*",
      ]
      resources = [
        format("arn:%s:kms:*:%s:key/*", join("", data.aws_partition.current[*].partition), join("", data.aws_caller_identity.this[*].account_id))
      ]
      principals {
        type = "AWS"
        identifiers = [
          format("arn:${join("", data.aws_partition.current[*].partition)}:iam::%s:root", local.audit_account_id)
        ]
      }
    }
  }
}


#
# ONLY EDIT THIS FILE IN github.com/cloudposse/terraform-null-label
# All other instances of this file should be a copy of that one
#
#
# Copy this file from https://github.com/cloudposse/terraform-null-label/blob/master/exports/context.tf
# and then place it in your Terraform module to automatically get
# Cloud Posse's standard configuration inputs suitable for passing
# to Cloud Posse modules.
#
# curl -sL https://raw.githubusercontent.com/cloudposse/terraform-null-label/master/exports/context.tf -o context.tf
#
# Modules should access the whole context as `module.this.context`
# to get the input variables with nulls for defaults,
# for example `context = module.this.context`,
# and access individual variables as `module.this.<var>`,
# with final values filled in.
#
# For example, when using defaults, `module.this.context.delimiter`
# will be null, and `module.this.delimiter` will be `-` (hyphen).
#

module "this" {
  source = "github.com/cloudposse/terraform-null-label.git?ref=0.25.0"

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

# Copy contents of cloudposse/terraform-null-label/variables.tf here

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
    # Note: we have to use [] instead of null for unset lists due to
    # https://github.com/hashicorp/terraform/issues/28137
    # which was not fixed until Terraform 1.0.0,
    # but we want the default to be all the labels in `label_order`
    # and we want users to be able to prevent all tag generation
    # by setting `labels_as_tags` to `[]`, so we need
    # a different sentinel to indicate "default"
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

#### End of copy of cloudposse/terraform-null-label/variables.tf


locals {
  enabled = module.this.enabled
}

module "cloudtrail" {
  source = "github.com/cloudposse/terraform-aws-cloudtrail.git?ref=0.21.0"

  cloud_watch_logs_role_arn     = join("", aws_iam_role.cloudtrail_cloudwatch_logs[*].arn)
  cloud_watch_logs_group_arn    = "${join("", aws_cloudwatch_log_group.cloudtrail_cloudwatch_logs[*].arn)}:*"
  enable_logging                = var.enable_logging
  enable_log_file_validation    = var.enable_log_file_validation
  include_global_service_events = var.include_global_service_events
  is_multi_region_trail         = var.is_multi_region_trail
  is_organization_trail         = var.is_organization_trail
  s3_bucket_name                = module.cloudtrail_bucket.outputs.cloudtrail_bucket_id
  kms_key_arn                   = module.kms_key_cloudtrail.key_arn

  context = module.this.context
}


output "cloudtrail_id" {
  value       = module.cloudtrail.cloudtrail_id
  description = "CloudTrail ID"
}

output "cloudtrail_arn" {
  value       = module.cloudtrail.cloudtrail_arn
  description = "CloudTrail ARN"
}

output "cloudtrail_home_region" {
  value       = module.cloudtrail.cloudtrail_home_region
  description = "The region in which CloudTrail was created"
}

output "cloudtrail_logs_log_group_arn" {
  value       = local.enabled ? join("", aws_cloudwatch_log_group.cloudtrail_cloudwatch_logs[*].arn) : null
  description = "CloudTrail Logs log group ARN"
}

output "cloudtrail_logs_log_group_name" {
  value       = local.enabled ? join("", aws_cloudwatch_log_group.cloudtrail_cloudwatch_logs[*].name) : null
  description = "CloudTrail Logs log group name"
}

output "cloudtrail_logs_role_arn" {
  value       = local.enabled ? join("", aws_iam_role.cloudtrail_cloudwatch_logs[*].arn) : null
  description = "CloudTrail Logs role ARN"
}

output "cloudtrail_logs_role_name" {
  value       = local.enabled ? join("", aws_iam_role.cloudtrail_cloudwatch_logs[*].name) : null
  description = "CloudTrail Logs role name"
}


provider "aws" {
  region = var.region

  # Profile is deprecated in favor of terraform_role_arn. When profiles are not in use, terraform_profile_name is null.
  profile = module.iam_roles.terraform_profile_name

  dynamic "assume_role" {
    # module.iam_roles.terraform_role_arn may be null, in which case do not assume a role.
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


module "cloudtrail_bucket" {
  source = "github.com/cloudposse/terraform-yaml-stack-config.git//modules/remote-state?ref=1.5.0"

  component   = var.cloudtrail_bucket_component_name
  environment = var.cloudtrail_bucket_environment_name
  stage       = var.cloudtrail_bucket_stage_name

  context = module.this.context
}

module "account_map" {
  source = "github.com/cloudposse/terraform-yaml-stack-config.git//modules/remote-state?ref=1.5.0"

  component   = "account-map"
  tenant      = module.iam_roles.global_tenant_name
  environment = module.iam_roles.global_environment_name
  stage       = module.iam_roles.global_stage_name

  context = module.this.context
}


variable "region" {
  type        = string
  description = "AWS Region"
}

variable "cloudwatch_logs_retention_in_days" {
  type        = number
  default     = 365
  description = "Number of days to retain logs for. CIS recommends 365 days.  Possible values are: 0, 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, and 3653. Set to 0 to keep logs indefinitely."
}

variable "enable_logging" {
  type        = bool
  default     = true
  description = "Enable logging for the trail"
}

variable "enable_log_file_validation" {
  type        = bool
  default     = true
  description = "Specifies whether log file integrity validation is enabled. Creates signed digest for validated contents of logs"
}

variable "include_global_service_events" {
  type        = bool
  default     = true
  description = "Specifies whether the trail is publishing events from global services such as IAM to the log files"
}

variable "is_multi_region_trail" {
  type        = bool
  default     = true
  description = "Specifies whether the trail is created in the current region or in all regions"
}

variable "cloudtrail_cloudwatch_logs_role_max_session_duration" {
  type        = number
  default     = 43200
  description = "The maximum session duration (in seconds) for the CloudTrail CloudWatch Logs role. Can have a value from 1 hour to 12 hours"
}

variable "cloudtrail_bucket_component_name" {
  type        = string
  description = "The name of the CloudTrail bucket component"
  default     = "cloudtrail-bucket"
}

variable "cloudtrail_bucket_environment_name" {
  type        = string
  description = "The name of the environment where the CloudTrail bucket is provisioned"
}

variable "cloudtrail_bucket_stage_name" {
  type        = string
  description = "The stage name where the CloudTrail bucket is provisioned"
}

variable "is_organization_trail" {
  type        = bool
  default     = false
  description = <<-EOT
  Specifies whether the trail is created for all accounts in an organization in AWS Organizations, or only for the current AWS account.

  The default is false, and cannot be true unless the call is made on behalf of an AWS account that is the management account
  for an organization in AWS Organizations.
  EOT
}

variable "audit_access_enabled" {
  type        = bool
  default     = false
  description = "If `true`, allows the Audit account access to read Cloudtrail logs directly from S3. This is a requirement for running Athena queries in the Audit account."
}


terraform {
  required_version = ">= 1.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 4.9.0"
    }
  }
}