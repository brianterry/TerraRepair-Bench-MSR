module "aurora_mysql" {
  source = "github.com/cloudposse/terraform-aws-rds-cluster.git?ref=a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0"

  attributes = [var.mysql_name]

  engine              = var.aurora_mysql_engine
  engine_version      = var.aurora_mysql_engine_version
  cluster_family      = var.aurora_mysql_cluster_family
  cluster_parameters  = var.aurora_mysql_cluster_parameters
  cluster_size        = var.mysql_cluster_size
  cluster_type        = "regional"
  instance_parameters = var.aurora_mysql_instance_parameters
  instance_type       = var.mysql_instance_type

  db_name        = local.mysql_db_name
  db_port        = 3306
  admin_password = local.mysql_admin_password
  admin_user     = local.mysql_admin_user

  vpc_id                     = local.vpc_id
  publicly_accessible        = var.publicly_accessible
  subnets                    = var.publicly_accessible ? local.public_subnet_ids : local.private_subnet_ids
  allowed_cidr_blocks        = local.allowed_cidr_blocks
  allowed_egress_cidr_blocks = local.allowed_cidr_blocks
  security_groups            = local.eks_cluster_managed_security_group_ids

  zone_id          = local.zone_id
  cluster_dns_name = "master.${local.cluster_subdomain}"
  reader_dns_name  = "readers.${local.cluster_subdomain}"

  auto_minor_version_upgrade      = var.auto_minor_version_upgrade
  deletion_protection             = var.mysql_deletion_protection
  enabled_cloudwatch_logs_exports = var.mysql_enabled_cloudwatch_logs_exports
  copy_tags_to_snapshot           = true
  skip_final_snapshot             = var.mysql_skip_final_snapshot

  backup_window      = var.mysql_backup_window
  maintenance_window = var.mysql_maintenance_window
  retention_period   = var.mysql_backup_retention_period

  storage_encrypted               = var.mysql_storage_encrypted
  kms_key_arn                     = var.mysql_storage_encrypted ? local.kms_key_arn : null
  performance_insights_enabled    = var.performance_insights_enabled
  performance_insights_kms_key_id = var.performance_insights_enabled ? local.kms_key_arn : null

  replication_source_identifier = local.replication_source_identifier

  context = module.this.context
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
  source = "github.com/cloudposse/terraform-null-label.git?ref=b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1"

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


module "kms_key_rds" {
  source = "github.com/cloudposse/terraform-aws-kms-key.git?ref=c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2"

  description             = "KMS key for Aurora MySQL"
  deletion_window_in_days = 10
  enable_key_rotation     = true
  policy                  = join("", data.aws_iam_policy_document.kms_key_rds.*.json)

  context = module.cluster.context
}

data "aws_caller_identity" "current" {
  count = local.enabled ? 1 : 0
}

data "aws_partition" "current" {
  count = local.enabled ? 1 : 0
}

# https://docs.aws.amazon.com/kms/latest/developerguide/key-policies.html#key-policy-default-allow-administrators
# https://aws.amazon.com/premiumsupport/knowledge-center/update-key-policy-future/
data "aws_iam_policy_document" "kms_key_rds" {
  count = local.enabled ? 1 : 0

  statement {
    sid    = "Enable the account that owns the KMS key to manage it via IAM"
    effect = "Allow"

    actions = [
      "kms:Create*",
      "kms:Describe*",
      "kms:Enable*",
      "kms:List*",
      "kms:Put*",
      "kms:Update*",
      "kms:Revoke*",
      "kms:Disable*",
      "kms:Get*",
      "kms:Delete*",
      "kms:TagResource",
      "kms:UntagResource",
      "kms:ScheduleKeyDeletion",
      "kms:CancelKeyDeletion"
    ]

    resources = [
      "*"
    ]

    principals {
      type = "AWS"

      identifiers = [
        format("arn:${join("", data.aws_partition.current.*.partition)}:iam::%s:root", join("", data.aws_caller_identity.current.*.account_id))
      ]
    }

    condition {
      test     = "StringEquals"
      variable = "kms:CallerAccount"
      values   = [join("", data.aws_caller_identity.current.*.account_id)]
    }
  }

  # https://docs.aws.amazon.com/kms/latest/developerguide/key-policies.html
  # https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_policies_elements_principal.html
  # https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_aws-services-that-work-with-iam.html
  # https://docs.aws.amazon.com/efs/latest/ug/using-service-linked-roles.html
  statement {
    sid    = "Allow RDS to encrypt and decrypt with the KMS key"
    effect = "Allow"

    actions = [
      "kms:Encrypt*",
      "kms:Decrypt*",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:Describe*",
      "kms:CreateGrant"
    ]

    resources = [
      "*"
    ]

    principals {
      type = "Service"

      identifiers = [
        "rds.amazonaws.com"
      ]
    }

    condition {
      test     = "Bool"
      variable = "kms:GrantIsForAWSResource"
      values   = ["true"]
    }

    condition {
      test     = "StringEquals"
      variable = "kms:CallerAccount"
      values   = [join("", data.aws_caller_identity.current.*.account_id)]
    }
  }
}


locals {
  enabled = module.this.enabled

  vpc_outputs           = module.vpc.outputs
  dns_delegated_outputs = module.dns-delegated.outputs
  vpc_id                = local.vpc_outputs.vpc_id
  public_subnet_ids     = local.vpc_outputs.public_subnet_ids
  private_subnet_ids    = local.vpc_outputs.private_subnet_ids
  zone_id               = local.dns_delegated_outputs.default_dns_zone_id

  eks_cluster_managed_security_group_ids = [for cluster in module.eks : cluster.outputs.eks_cluster_managed_security_group_id]

  # Read Replication uses either an explicit ARN of the replication source or Remote State from the primary region
  is_read_replica             = local.enabled && var.is_read_replica
  remote_read_replica_enabled = local.is_read_replica && !(length(var.replication_source_identifier) > 0) && length(var.primary_cluster_region) > 0

  # Removing the replicate source attribute from an existing RDS Replicate database managed by Terraform
  # should promote the database to a fully standalone database but currently is not supported by Terraform.
  # Instead, first manually promote with the AWS CLI or console, and then remove the replication source identitier from the Terrafrom state
  # See https://github.com/hashicorp/terraform-provider-aws/issues/6749
  replication_source_identifier = local.remote_read_replica_enabled && !var.is_promoted_read_replica ? module.primary_cluster[0].outputs.aurora_mysql_cluster_arn : var.replication_source_identifier

  # For encrypted cross-region replica, kmsKeyId should be explicitly specified
  # https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/Overview.Encryption.html
  # A read replica of an Amazon RDS encrypted instance must be encrypted using the same KMS key as the primary DB instance when both are in the same AWS Region.
  # If the primary DB instance and read replica are in different AWS Regions, you encrypt the read replica using a KMS key in that AWS Region.
  kms_key_arn = module.kms_key_rds.key_arn

  # Do not create a DB & DB resources if Read Replication is enabled
  mysql_db_enabled     = local.enabled && !local.is_read_replica
  mysql_db_name        = length(var.mysql_db_name) > 0 ? var.mysql_db_name : join("", random_pet.mysql_db_name.*.id)
  mysql_admin_user     = length(var.mysql_admin_user) > 0 ? var.mysql_admin_user : join("", random_pet.mysql_admin_user.*.id)
  fetch_admin_password = local.mysql_db_enabled && length(var.ssm_password_source) > 0
  mysql_admin_password = local.fetch_admin_password ? data.aws_ssm_parameter.password[0].value : (
    length(var.mysql_admin_password) > 0 ? var.mysql_admin_password : join("", random_password.mysql_admin_password.*.result)
  )

  cluster_domain    = trimprefix(module.aurora_mysql.endpoint, "${module.aurora_mysql.cluster_identifier}.cluster-")
  cluster_subdomain = var.mysql_name == "" ? module.this.name : "${var.mysql_name}.${module.this.name}"

  # Join a list of all allowed cidr blocks from:
  # 1. VPCs from all given accounts
  # 2. Additionally given CIDR blocks
  all_allowed_cidr_blocks = concat(
    var.allowed_cidr_blocks,
    [
      for k in keys(module.vpc_ingress) :
      module.vpc_ingress[k].outputs.vpc_cidr
    ]
  )
  allowed_cidr_blocks = var.publicly_accessible ? coalescelist(local.all_allowed_cidr_blocks, ["0.0.0.0/0"]) : local.all_allowed_cidr_blocks
}

module "cluster" {
  source = "github.com/cloudposse/terraform-null-label.git?ref=b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1"

  attributes = [var.mysql_name]

  context = module.this.context
}

resource "random_pet" "mysql_admin_user" {
  count     = local.mysql_db_enabled && length(var.mysql_admin_user) == 0 ? 1 : 0
  length    = 2
  separator = "_"
}

resource "random_password" "mysql_admin_password" {
  count   = local.mysql_db_enabled && length(var.mysql_admin_password) == 0 && local.fetch_admin_password == false ? 1 : 0
  length  = 33
  special = false
}

resource "random_pet" "mysql_db_name" {
  count = local.mysql_db_enabled && length(var.mysql_db_name) == 0 ? 1 : 0

  separator = "_"

  keepers = {
    cluster_name = var.mysql_name
    db_name      = var.mysql_db_name
  }
}


output "aurora_mysql_cluster_arn" {
  value       = module.aurora_mysql.arn
  description = "The ARN of Aurora cluster"
}

output "aurora_mysql_cluster_id" {
  value       = module.cluster.id
  description = "The ID of Aurora cluster"
}

output "aurora_mysql_cluster_name" {
  value       = local.enabled ? module.aurora_mysql.cluster_identifier : null
  description = "Aurora MySQL cluster identifier"
}

output "aurora_mysql_endpoint" {
  value       = local.enabled ? module.aurora_mysql.endpoint : null
  description = "Aurora MySQL endpoint"
}

output "aurora_mysql_master_hostname" {
  value       = local.enabled ? module.aurora_mysql.master_host : null
  description = "Aurora MySQL DB master hostname"
}

output "aurora_mysql_master_password" {
  value       = local.mysql_db_enabled ? "Password for admin user ${module.aurora_mysql.master_username} is stored in SSM at ${local.mysql_admin_password_key}" : null
  description = "Location of admin password in SSM"
  sensitive   = true
}

output "aurora_mysql_master_password_ssm_key" {
  value       = local.mysql_db_enabled ? local.mysql_admin_password_key : null
  description = "SSM key for admin password"
}

output "aurora_mysql_master_username" {
  value       = local.enabled ? module.aurora_mysql.master_username : null
  description = "Aurora MySQL username for the master DB user"
  sensitive   = true
}

output "aurora_mysql_reader_endpoint" {
  value       = local.enabled ? module.aurora_mysql.reader_endpoint : null
  description = "Aurora MySQL reader endpoint"
}

output "aurora_mysql_replicas_hostname" {
  value       = local.enabled ? module.aurora_mysql.replicas_host : null
  description = "Aurora MySQL replicas hostname"
}

output "cluster_domain" {
  value       = local.cluster_domain
  description = "Cluster DNS name"
}

output "kms_key_arn" {
  value       = module.kms_key_rds.key_arn
  description = "KMS key ARN for Aurora MySQL"
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


locals {
  accounts_with_vpc = { for i, account in var.allow_ingress_from_vpc_accounts : try(account.tenant, module.this.tenant) != null ? format("%s-%s", account.tenant, account.stage) : account.stage => account }
}

module "dns-delegated" {
  source = "github.com/cloudposse/terraform-yaml-stack-config.git//modules/remote-state?ref=d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3"

  component   = "dns-delegated"
  environment = "gbl"

  context = module.this.context
}

module "eks" {
  source = "github.com/cloudposse/terraform-yaml-stack-config.git//modules/remote-state?ref=d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3"

  for_each = var.eks_component_names

  component = each.value

  context = module.this.context
}

module "vpc" {
  source = "github.com/cloudposse/terraform-yaml-stack-config.git//modules/remote-state?ref=d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3"

  component = var.vpc_component_name

  context = module.this.context
}

module "vpc_ingress" {
  source = "github.com/cloudposse/terraform-yaml-stack-config.git//modules/remote-state?ref=d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3"

  for_each = local.accounts_with_vpc

  component   = each.value.vpc
  environment = try(each.value.environment, module.this.environment)
  stage       = try(each.value.stage, module.this.environment)
  tenant      = try(each.value.tenant, module.this.tenant)

  context = module.this.context
}


module "primary_cluster" {
  source = "github.com/cloudposse/terraform-yaml-stack-config.git//modules/remote-state?ref=d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3"

  count = local.remote_read_replica_enabled ? 1 : 0

  component   = var.primary_cluster_component
  environment = var.primary_cluster_region

  context = module.this.context
}


locals {
  ssm_path_prefix = format("/%s/%s", var.ssm_path_prefix, module.cluster.id)

  mysql_admin_user_key     = format("%s/%s/%s", local.ssm_path_prefix, "admin", "user")
  mysql_admin_password_key = format("%s/%s/%s", local.ssm_path_prefix, "admin", "password")

  default_parameters = [
    {
      name        = format("%s/%s", local.ssm_path_prefix, "cluster_domain")
      value       = local.cluster_domain
      description = "AWS DNS name under which DB instances are provisioned"
      type        = "String"
      overwrite   = true
    },
    {
      name        = format("%s/%s", local.ssm_path_prefix, "db_host")
      value       = module.aurora_mysql.master_host
      description = "Aurora MySQL DB Master hostname"
      type        = "String"
      overwrite   = true
    },
    {
      name        = format("%s/%s", local.ssm_path_prefix, "db_port")
      value       = "3306"
      description = "Aurora MySQL DB Master TCP port"
      type        = "String"
      overwrite   = true
    },
    {
      name        = format("%s/%s", local.ssm_path_prefix, "cluster_name")
      value       = module.aurora_mysql.cluster_identifier
      description = "Aurora MySQL DB Cluster Identifier"
      type        = "String"
      overwrite   = true
    }
  ]
  cluster_parameters = var.mysql_cluster_size > 0 ? [
    {
      name        = format("%s/%s", local.ssm_path_prefix, "replicas_hostname")
      value       = module.aurora_mysql.replicas_host
      description = "Aurora MySQL DB Replicas hostname"
      type        = "String"
      overwrite   = true
    },
  ] : []
  admin_user_parameters = [
    {
      name        = local.mysql_admin_user_key
      value       = local.mysql_admin_user
      description = "Aurora MySQL DB admin user"
      type        = "String"
      overwrite   = true
    },
    {
      name        = local.mysql_admin_password_key
      value       = local.mysql_admin_password
      description = "Aurora MySQL DB admin password"
      type        = "SecureString"
      overwrite   = true
    }
  ]

  parameter_write = local.mysql_db_enabled ? concat(local.default_parameters, local.cluster_parameters, local.admin_user_parameters) : concat(local.default_parameters, local.cluster_parameters)
}

data "aws_ssm_parameter" "password" {
  count = local.fetch_admin_password ? 1 : 0

  name = format(var.ssm_password_source, local.mysql_admin_user)

  with_decryption = true
}

module "parameter_store_write" {
  source = "github.com/cloudposse/terraform-aws-ssm-parameter-store.git?ref=e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4"

  # kms_arn will only be used for SecureString parameters
  kms_arn = module.kms_key_rds.key_arn

  parameter_write = local.parameter_write

  context = module.cluster.context
}


variable "region" {
  type        = string
  description = "AWS Region"
}

variable "ssm_path_prefix" {
  type        = string
  default     = "rds"
  description = "SSM path prefix"
}

variable "ssm_password_source" {
  type        = string
  default     = ""
  description = <<-EOT
    If `var.ssm_passwords_enabled` is `true`, DB user passwords will be retrieved from SSM using
    `var.ssm_password_source` and the database username. If this value is not set,
    a default path will be created using the SSM path prefix and ID of the associated Aurora Cluster.
    EOT
}

variable "allowed_cidr_blocks" {
  type        = list(string)
  default     = []
  description = "List of CIDR blocks to be allowed to connect to the RDS cluster"
}

variable "mysql_name" {
  type        = string
  description = "MySQL solution name (part of cluster identifier)"
  default     = ""
}

variable "mysql_db_name" {
  type        = string
  description = "Database name (default is not to create a database"
  default     = ""
}

variable "mysql_admin_user" {
  type        = string
  description = "MySQL admin user name"
  default     = ""
}

variable "mysql_admin_password" {
  type        = string
  description = "MySQL password for the admin user"
  default     = ""
}

# https://aws.amazon.com/rds/RDS/pricing
variable "mysql_instance_type" {
  type        = string
  default     = "db.t3.medium"
  description = "EC2 instance type for RDS MySQL cluster"
}

variable "aurora_mysql_engine" {
  type        = string
  description = "Engine for Aurora database: `aurora` for MySQL 5.6, `aurora-mysql` for MySQL 5.7"
}

variable "aurora_mysql_engine_version" {
  type        = string
  description = "Engine Version for Aurora database."
  default     = ""
}

variable "aurora_mysql_cluster_family" {
  type        = string
  description = "DBParameterGroupFamily (e.g. `aurora5.6`, `aurora-mysql5.7` for Aurora MySQL databases). See https://stackoverflow.com/a/55819394 for help finding the right one to use."
}

variable "aurora_mysql_cluster_parameters" {
  type = list(object({
    apply_method = string
    name         = string
    value        = string
  }))
  default     = []
  description = "List of DB cluster parameters to apply"
}

variable "aurora_mysql_instance_parameters" {
  type = list(object({
    apply_method = string
    name         = string
    value        = string
  }))
  default     = []
  description = "List of DB instance parameters to apply"
}

variable "mysql_cluster_size" {
  type        = string
  default     = 2
  description = "MySQL cluster size"
}

variable "mysql_storage_encrypted" {
  type        = string
  default     = true
  description = "Set to `true` to keep the database contents encrypted"
}

variable "mysql_deletion_protection" {
  type        = string
  default     = true
  description = "Set to `true` to protect the database from deletion"
}

variable "mysql_skip_final_snapshot" {
  type        = string
  default     = false
  description = "Determines whether a final DB snapshot is created before the DB cluster is deleted"
}

variable "mysql_enabled_cloudwatch_logs_exports" {
  type        = list(string)
  description = "List of log types to export to cloudwatch. The following log types are supported: audit, error, general, slowquery"
  default     = ["audit", "error", "general", "slowquery"]
}

variable "performance_insights_enabled" {
  type        = bool
  description = "Set `true` to enable Performance Insights"
  default     = true
}

variable "mysql_backup_retention_period" {
  type        = number
  default     = 3
  description = "Number of days for which to retain backups"
}

variable "mysql_backup_window" {
  type        = string
  default     = "07:00-09:00"
  description = "Daily time range during which the backups happen"
}

variable "mysql_maintenance_window" {
  type        = string
  default     = "sat:10:00-sat:10:30"
  description = "Weekly time range during which system maintenance can occur, in UTC"
}

variable "auto_minor_version_upgrade" {
  type        = bool
  default     = false
  description = "Automatically update the cluster when a new minor version is released"
}

variable "publicly_accessible" {
  type        = bool
  default     = false
  description = "Set to true to create the cluster in a public subnet"
}

variable "eks_component_names" {
  type        = set(string)
  description = "The names of the eks components"
  default     = ["eks/cluster"]
}

variable "replication_source_identifier" {
  type        = string
  description = <<-EOT
    ARN of a source DB cluster or DB instance if this DB cluster is to be created as a Read Replica.
    If this value is empty and replication is enabled, remote state will attempt to find
    a matching cluster in the Primary DB Cluster's region
    EOT
  default     = ""
}

variable "is_read_replica" {
  type        = bool
  description = "If `true`, create this DB cluster as a Read Replica."
  default     = false
}

variable "is_promoted_read_replica" {
  type        = bool
  description = "If `true`, do not assign a Replication Source to the Cluster. Set to `true` after manually promoting the cluster from a replica to a standalone cluster."
  default     = false
}

variable "primary_cluster_region" {
  type        = string
  description = "If this cluster is a read replica and no replication source is explicitly given, the region to look for a matching cluster"
  default     = ""
}

variable "primary_cluster_component" {
  type        = string
  description = "If this cluster is a read replica and no replication source is explicitly given, the component name for the primary cluster"
  default     = "aurora-mysql"
}

variable "allow_ingress_from_vpc_accounts" {
  type = list(object({
    vpc         = optional(string, "vpc")
    environment = optional(string)
    stage       = optional(string)
    tenant      = optional(string)
  }))
  default     = []
  description = <<-EOF
    List of account contexts to pull VPC ingress CIDR and add to cluster security group.

    e.g.
    {
      environment = "ue2",
      stage       = "auto",
      tenant      = "core"
    }

    Defaults to the "vpc" component in the given account
  EOF
}

variable "vpc_component_name" {
  type        = string
  default     = "vpc"
  description = "The name of the VPC component"
}


terraform {
  required_version = ">= 1.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 2.2"
    }
  }
}