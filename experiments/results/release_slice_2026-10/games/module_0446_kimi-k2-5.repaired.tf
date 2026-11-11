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
  source  = "cloudposse/label/null"
  version = "0.25.0" # requires Terraform >= 0.13.0

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
  access_roles = local.enabled ? {
    for k, v in var.access_roles : (
      length(split(module.this.delimiter, k)) > 1 ? k : module.label[k].id
    ) => v
  } : {}

  access_roles_enabled      = local.enabled && var.access_roles_enabled
  cold_start_access_enabled = local.enabled && !var.access_roles_enabled

  # Technically, `eks_role_arn` is incorrect, because it strips any path from the ARN,
  # but since we do not expect there to be a path in the role ARN (as opposed to perhaps an attached IAM policy),
  # it is OK. The advantage of using `eks_role_arn` is that it converts and Assumed Role ARN from STS, like
  #    arn:aws:sts::123456789012:assumed-role/acme-core-gbl-root-admin/aws-go-sdk-1722029959251053170
  # to the IAM Role ARN, like
  #    arn:aws:iam::123456789012:role/acme-core-gbl-root-admin
  caller_arn = coalesce(data.awsutils_caller_identity.current.eks_role_arn, data.awsutils_caller_identity.current.arn)
}

data "awsutils_caller_identity" "current" {}
data "aws_partition" "current" {}


module "label" {
  for_each = local.enabled ? var.access_roles : {}
  source   = "cloudposse/label/null"
  version  = "0.25.0" # requires Terraform >= 0.13.0

  enabled = length(split(module.this.delimiter, each.key)) == 1

  environment = "gbl"
  attributes  = contains(["default", "terraform"], each.key) ? [] : [each.key]
  # Support backward compatibility with old `iam-delegated-roles`
  name = each.key == "terraform" ? "terraform" : null

  context = module.this.context
}

module "assume_role" {
  for_each = local.access_roles_enabled ? local.access_roles : {}
  source   = "../account-map/modules/team-assume-role-policy"

  allowed_roles = each.value.allowed_roles
  denied_roles  = each.value.denied_roles

  # Allow whatever user or role is running Terraform to manage the backend to assume any backend access role
  allowed_principal_arns = distinct(concat(each.value.allowed_principal_arns, [local.caller_arn]))
  denied_principal_arns  = each.value.denied_principal_arns
  # Permission sets are for AWS SSO, which is optional
  allowed_permission_sets = try(each.value.allowed_permission_sets, {})
  denied_permission_sets  = try(each.value.denied_permission_sets, {})

  privileged = true

  context = module.this.context
}

data "aws_iam_policy_document" "tfstate" {
  for_each = local.access_roles

  statement {
    sid     = "TerraformStateBackendS3Bucket"
    effect  = "Allow"
    actions = concat(["s3:ListBucket", "s3:GetObject"], each.value.write_enabled ? ["s3:PutObject", "s3:DeleteObject"] : [])
    resources = [
      module.tfstate_backend.s3_bucket_arn,
      "${module.tfstate_backend.s3_bucket_arn}/*"
    ]
  }

  statement {
    sid    = "TerraformStateBackendDynamoDbTable"
    effect = "Allow"
    # Even readers need to be able to write to the Dynamo table to lock the state while planning
    # actions   = concat(["dynamodb:GetItem"], each.value.write_enabled ? ["dynamodb:PutItem", "dynamodb:DeleteItem"] : [])
    actions   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:DeleteItem"]
    resources = [module.tfstate_backend.dynamodb_table_arn]
  }
}

resource "aws_iam_role" "default" {
  for_each = local.access_roles

  name               = each.key
  description        = "${each.value.write_enabled ? "Access" : "Read-only access"} role for ${module.this.id}"
  assume_role_policy = var.access_roles_enabled ? module.assume_role[each.key].policy_document : data.aws_iam_policy_document.cold_start_assume_role[each.key].json
  tags               = merge(module.this.tags, { Name = each.key })

  inline_policy {
    name   = each.key
    policy = data.aws_iam_policy_document.tfstate[each.key].json
  }
  managed_policy_arns = []
}

locals {
  all_cold_start_access_principals = local.cold_start_access_enabled ? toset(concat([local.caller_arn],
  flatten([for k, v in local.access_roles : v.allowed_principal_arns]))) : toset([])
  cold_start_access_principal_arns = local.cold_start_access_enabled ? { for k, v in local.access_roles : k => distinct(concat(
    [local.caller_arn], v.allowed_principal_arns
  )) } : {}
  cold_start_access_principals = local.cold_start_access_enabled ? {
    for k, v in local.cold_start_access_principal_arns : k => formatlist("arn:%v:iam::%v:root", data.aws_partition.current.partition, distinct([
      for arn in v : data.aws_arn.cold_start_access[arn].account
    ]))
  } : {}

}

data "aws_arn" "cold_start_access" {
  for_each = local.all_cold_start_access_principals
  arn      = each.value
}

# This is a basic policy that allows the caller and explicitly allowed principals to assume the role
# during the period roles are being set up (cold start).
data "aws_iam_policy_document" "cold_start_assume_role" {
  for_each = local.cold_start_access_enabled ? local.access_roles : {}

  statement {
    sid = "ColdStartRoleAssumeRole"

    effect = "Allow"
    # These actions need to be kept in sync with the actions in the assume_role module
    actions = [
      "sts:AssumeRole",
      "sts:SetSourceIdentity",
      "sts:TagSession",
    ]

    condition {
      test     = "ArnLike"
      variable = "aws:PrincipalArn"
      values   = local.cold_start_access_principal_arns[each.key]
    }

    principals {
      type = "AWS"
      # Principals is a required field, so we allow any principal in any of the accounts, restricted by the assumed Role ARN in the condition clauses.
      # This allows us to allow non-existent (yet to be created) roles, which would not be allowed if directly specified in `principals`.
      identifiers = local.cold_start_access_principals[each.key]
    }
  }
}


locals {
  enabled = module.this.enabled
}

data "aws_kms_key" "s3" {
  key_id = var.kms_key_id
}

module "tfstate_backend" {
  source  = "cloudposse/tfstate-backend/aws"
  version = "1.1.0"

  force_destroy               = var.force_destroy
  prevent_unencrypted_uploads = var.prevent_unencrypted_uploads
  // enable_server_side_encryption = var.enable_server_side_encryption
  enable_point_in_time_recovery     = var.enable_point_in_time_recovery
  bucket_ownership_enforced_enabled = false

  s3_bucket_encryption_enabled     = true
  s3_bucket_encryption_key_arn     = data.aws_kms_key.s3.arn
  dynamodb_encryption_enabled      = true
  dynamodb_encryption_key_arn      = var.dynamodb_kms_key_id
  access_logging_bucket_name       = var.access_logging_bucket_name

  context = module.this.context
}


output "tfstate_backend_s3_bucket_domain_name" {
  description = "Terraform state S3 bucket domain name"
  value       = module.tfstate_backend.s3_bucket_domain_name
}

output "tfstate_backend_s3_bucket_id" {
  description = "Terraform state S3 bucket ID"
  value       = module.tfstate_backend.s3_bucket_id
}

output "tfstate_backend_s3_bucket_arn" {
  description = "Terraform state S3 bucket ARN"
  value       = module.tfstate_backend.s3_bucket_arn
}

output "tfstate_backend_dynamodb_table_name" {
  description = "Terraform state DynamoDB table name"
  value       = module.tfstate_backend.dynamodb_table_name
}

output "tfstate_backend_dynamodb_table_id" {
  description = "Terraform state DynamoDB table ID"
  value       = module.tfstate_backend.dynamodb_table_id
}

output "tfstate_backend_dynamodb_table_arn" {
  description = "Terraform state DynamoDB table ARN"
  value       = module.tfstate_backend.dynamodb_table_arn
}

output "tfstate_backend_access_role_arns" {
  value       = { for k, v in aws_iam_role.default : k => v.arn }
  description = "IAM Role ARNs for accessing the Terraform State Backend"
}


provider "aws" {
  region = var.region
}


variable "region" {
  type        = string
  description = "AWS Region"
}

variable "force_destroy" {
  type        = bool
  description = "A boolean that indicates the terraform state S3 bucket can be destroyed even if it contains objects. These objects are not recoverable."
  default     = false
}

variable "prevent_unencrypted_uploads" {
  type        = bool
  description = "Prevent uploads of unencrypted objects to S3"
  default     = true
}

variable "enable_server_side_encryption" {
  type        = bool
  description = "Enable DynamoDB and S3 server-side encryption"
  default     = true
}

variable "enable_point_in_time_recovery" {
  type        = bool
  description = "Enable DynamoDB point-in-time recovery"
  default     = true
}

variable "access_roles" {
  description = "Map of access roles to create (key is role name, use \"default\" for same as component). See iam-assume-role-policy module for details."
  type = map(object({
    write_enabled           = bool
    allowed_roles           = map(list(string))
    denied_roles            = map(list(string))
    allowed_principal_arns  = list(string)
    denied_principal_arns   = list(string)
    allowed_permission_sets = map(list(string))
    denied_permission_sets  = map(list(string))
  }))
  default = {}
}

variable "access_roles_enabled" {
  type        = bool
  description = <<-EOT
    Enable access roles to be assumed. Set `false` for cold start (before account-map has been created),
    because the role to ARN mapping has not yet been created.
    Note that the current caller and any `allowed_principal_arns` will always be allowed to assume the role.
    EOT
  default     = true
}

variable "kms_key_id" {
  type        = string
  description = "KMS Key ID for S3 bucket encryption"
  default     = "alias/aws/s3"
}

variable "dynamodb_kms_key_id" {
  type        = string
  description = "KMS Key ID for DynamoDB table encryption"
  default     = null
}

variable "access_logging_bucket_name" {
  type        = string
  description = "S3 bucket name for access logging"
  default     = null
}


terraform {
  required_version = ">= 1.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 4.9.0"
    }
    awsutils = {
      source  = "cloudposse/awsutils"
      version = ">= 0.16.0"
    }
  }
}