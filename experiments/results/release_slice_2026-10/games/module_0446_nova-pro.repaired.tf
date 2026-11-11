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

module "label" {
  for_each = local.enabled? var.access_roles : {}
  source   = "cloudposse/label/null"
  version  = "0.25.0"

  enabled = length(split(module.this.delimiter, each.key)) == 1

  environment = "gbl"
  attributes  = contains(["default", "terraform"], each.key)? [] : [each.key]
  name = each.key == "terraform"? "terraform" : null

  context = module.this.context
}

module "assume_role" {
  for_each = local.access_roles_enabled? local.access_roles : {}
  source   = "../account-map/modules/team-assume-role-policy"

  allowed_roles = each.value.allowed_roles
  denied_roles  = each.value.denied_roles
  allowed_principal_arns = distinct(concat(each.value.allowed_principal_arns, [local.caller_arn]))
  denied_principal_arns  = each.value.denied_principal_arns
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
    actions = concat(["s3:ListBucket", "s3:GetObject"], each.value.write_enabled? ["s3:PutObject", "s3:DeleteObject"] : [])
    resources = [
      module.tfstate_backend.s3_bucket_arn,
      "${module.tfstate_backend.s3_bucket_arn}/*"
    ]
  }

  statement {
    sid    = "TerraformStateBackendDynamoDbTable"
    effect = "Allow"
    actions   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:DeleteItem"]
    resources = [module.tfstate_backend.dynamodb_table_arn]
  }
}

resource "aws_iam_role" "default" {
  for_each = local.access_roles

  name               = each.key
  description        = "${each.value.write_enabled? "Access" : "Read-only access"} role for ${module.this.id}"
  assume_role_policy = var.access_roles_enabled? module.assume_role[each.key].policy_document : data.aws_iam_policy_document.cold_start_assume_role[each.key].json
  tags               = merge(module.this.tags, { Name = each.key })

  inline_policy {
    name   = each.key
    policy = data.aws_iam_policy_document.tfstate[each.key].json
  }
  managed_policy_arns = []
}

locals {
  all_cold_start_access_principals = local.cold_start_access_enabled? toset(concat([local.caller_arn], flatten([for k, v in local.access_roles : v.allowed_principal_arns]))) : toset([])
  cold_start_access_principal_arns = local.cold_start_access_enabled? { for k, v in local.access_roles : k => distinct(concat([local.caller_arn], v.allowed_principal_arns)) } : {}
  cold_start_access_principals = local.cold_start_access_enabled? { for k, v in local.cold_start_access_principal_arns : k => formatlist("arn:%v:iam::%v:root", data.aws_partition.current.partition, distinct([for arn in v : data.aws_arn.cold_start_access[arn].account])) } : {}
}

data "aws_arn" "cold_start_access" {
  for_each = local.all_cold_start_access_principals
  arn      = each.value
}

data "aws_iam_policy_document" "cold_start_assume_role" {
  for_each = local.cold_start_access_enabled? local.access_roles : {}

  statement {
    sid = "ColdStartRoleAssumeRole"

    effect = "Allow"
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
      identifiers = local.cold_start_access_principals[each.key]
    }
  }
}

locals {
  enabled = module.this.enabled
}

module "tfstate_backend" {
  source  = "cloudposse/tfstate-backend/aws"
  version = "1.1.0"

  force_destroy               = var.force_destroy
  prevent_unencrypted_uploads = var.prevent_unencrypted_uploads
  enable_server_side_encryption = var.enable_server_side_encryption
  enable_point_in_time_recovery     = var.enable_point_in_time_recovery
  bucket_ownership_enforced_enabled = false
  enable_logging = true
  kms_key_arn = "arn:aws:kms:<region>:<account-id>:key/<key-id>"

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