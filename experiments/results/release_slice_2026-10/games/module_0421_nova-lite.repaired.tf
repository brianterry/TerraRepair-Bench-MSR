```hcl
# A child module automatically inherits default (un-aliased) provider configurations from its parent.
# This means that explicit provider blocks appear only in the root module, and downstream modules can simply
# declare resources for that provider and have them automatically associated with the root provider configurations

# https://www.terraform.io/docs/providers/aws/r/rds_cluster.html
module "aurora_postgres_cluster" {
  source  = "cloudposse/rds-cluster/aws"
  version = "1.3.2"

  cluster_type   = "regional"
  engine         = var.engine
  engine_version = var.engine_version
  engine_mode    = var.engine_mode
  cluster_family = var.cluster_family
  instance_type  = var.instance_type
  cluster_size   = var.cluster_size
  admin_user     = local.admin_user
  admin_password = local.admin_password

  db_name                              = local.database_name
  publicly_accessible                  = var.publicly_accessible
  db_port                              = var.database_port
  vpc_id                               = local.vpc_id
  subnets                              = local.private_subnet_ids
  zone_id                              = local.zone_id
  cluster_dns_name                     = local.cluster_dns_name
  reader_dns_name                      = local.reader_dns_name
  security_groups                      = local.allowed_security_groups
  intra_security_group_traffic_enabled = var.intra_security_group_traffic_enabled
  allowed_cidr_blocks                  = local.allowed_cidr_blocks
  iam_database_authentication_enabled  = var.iam_database_authentication_enabled
  storage_encrypted                    = var.storage_encrypted
  kms_key_arn                          = var.storage_encrypted? module.kms_key_rds.key_arn : null
  performance_insights_kms_key_id      = var.performance_insights_enabled? module.kms_key_rds.key_arn : null
  maintenance_window                   = var.maintenance_window
  enabled_cloudwatch_logs_exports      = var.enabled_cloudwatch_logs_exports
  enhanced_monitoring_role_enabled     = var.enhanced_monitoring_role_enabled
  enhanced_monitoring_attributes       = var.enhanced_monitoring_attributes
  performance_insights_enabled           = true
  rds_monitoring_interval              = var.rds_monitoring_interval
  autoscaling_enabled                  = var.autoscaling_enabled
  autoscaling_policy_type              = var.autoscaling_policy_type
  autoscaling_target_metrics           = var.autoscaling_target_metrics
  autoscaling_target_value             = var.autoscaling_target_value
  autoscaling_scale_in_cooldown        = var.autoscaling_scale_in_cooldown
  autoscaling_scale_out_cooldown       = var.autoscaling_scale_out_cooldown
  autoscaling_min_capacity             = var.autoscaling_min_capacity
  autoscaling_max_capacity             = var.autoscaling_max_capacity
  scaling_configuration                = var.scaling_configuration
  serverlessv2_scaling_configuration   = var.serverlessv2_scaling_configuration
  skip_final_snapshot                  = var.skip_final_snapshot
  deletion_protection                  = var.deletion_protection? var.deletion_protection : true
  allow_major_version_upgrade          = var.allow_major_version_upgrade
  ca_cert_identifier                   = var.ca_cert_identifier
  retention_period                    = var.retention_period
  backup_window                        = var.backup_window

  cluster_parameters = concat([
    {
      apply_method = "immediate"
      name         = "log_statement"
      value        = "all"
    },
    {
      apply_method = "immediate"
      name         = "log_min_duration_statement"
      value        = "0"
    }
  ], var.cluster_parameters)

  context = module.cluster.context
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
# for example `module.this.context`,
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
    condition     = lookup(var.context, "label_key_case", null) == null? true : contains(["lower", "title", "upper"], var.context["label_key_case"])
    error_message = "Allowed values: `lower`, `title`, `upper`."
  }

  validation {
    condition     = lookup(var.context, "label_value_case", null) == null? true : contains(["lower", "title", "upper", "none"], var.context["label_value_case"])
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
    condition     = var.id_length_limit == null? true : var.id_length_limit >= 6 || var.id_length_limit == 0
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
    condition     = var.label_key_case == null? true : contains(["lower", "title", "upper"], var.label_key_case)
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
    condition     = var.label_value_case == null? true : contains(["lower", "title", "upper", "none"], var.label_value_case)
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
  source  = "cloudposse/kms-key/aws"
  version = "0.12.1"

  description             = "KMS key for Aurora Postgres"
  deletion_window_in_days = 10
  enable_key_rotation     = true
  policy                  = join("", data.aws_iam_policy_document.kms_key_rds.*.json)

  context = module.cluster.context
}

data "aws_caller_identity" "current" {
  count = local.enabled? 1 : 0
}

data "aws_partition" "current" {
  count = local.enabled? 1 : 0
}

# https://docs.aws.amazon.com/kms/latest/developerguide/key-policies.html#key-policy-default-allow-administrators
# https://aws.amazon.com/premiumsupport/knowledge-center/update-key-policy-future/
data "aws_iam_policy_document" "kms_key_rds" {
  count = local.enabled? 1 : 0

  statement {
    sid    = "Enable the account that owns the KMS key to manage it via IAM"
    effect = "Allow"

    actions = [
      "kms:*"
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
      "kms:Describe*"
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
  }

  statement {
    sid    = "Restrict S3 actions to specific buckets"
    effect = "Deny"

    actions = [
      "s3:*"
    ]

    resources = [
      "*"
    ]

    condition {
      test     = "StringNotEquals"
      variable = "aws:ResourceTag/Environment"
      values   = ["prod"]
    }
  }
}


locals {
  enabled = module.this.enabled

  vpc_id             = module.vpc.outputs.vpc_id
  private_subnet_ids = module.vpc.outputs.private_subnet_ids

  eks_security_group_enabled = local.enabled && var.eks_security_group_enabled
  allowed_eks_security_groups = [
    for eks in module.eks :
    eks.outputs.eks_cluster_managed_security_group_id
  ]
  allowed_security_groups = concat(data.aws_security_groups.allowed.ids, local.allowed_eks_security_groups)

  zone_id = module.dns_gbl_delegated.outputs.default_dns_zone_id

  admin_user     = length(var.admin_user) > 0? var.admin_user : join("", random_pet.admin_user[*].id)
  admin_password = length(var.admin_password) > 0? var.admin_password : join("", random_password.admin_password[*].result)
  database_name  = length(var.database_name) > 0? var.database_name : join("", random_pet.database_name[*].id)

  cluster_dns_name_prefix = format("%v%v%v%v", module.this.name, module.this.delimiter, var.cluster_name, module.this.delimiter)
  cluster_dns_name        = format("%v%v", local.cluster_dns_name_prefix, var.cluster_dns_name_part)
  reader_dns_name         = format("%v%v", local.cluster_dns_name_prefix, var.reader_dns_name_part)

  allowed_cidr_blocks = concat(
    var.allowed_cidr_blocks,
    [
      for k in keys(module.vpc_ingress) :
      module.vpc_ingress[k].outputs.vpc_cidr
    ]
  )
}

data "aws_security_groups" "allowed" {
  filter {
    name   = "tag:Name"
    values = var.allowed_security_group_names
  }
}

module "cluster" {
  source  = "cloudposse/label/null"
  version = "0.25.0"

  attributes = [var.cluster_name]

  context = module.this.context
}

resource "random_pet" "database_name" {
  count = local.enabled && length(var.database_name) == 0? 1 : 0

  separator = "_"

  keepers = {
    cluster_name = var.cluster_name
    db_name      = var.database_name
  }
}

resource "random_pet" "admin_user" {
  count = local.enabled && length(var.admin_user) == 0? 1 : 0

  length    = 2
  separator = "_"

  keepers = {
    cluster_name = var.cluster_name
    db_name      = var.database_name
  }
}

resource "random_password" "admin_password" {
  count = local.enabled && length(var.admin_password) == 0? 1 : 0

  length = 33
  # Leave special characters out to avoid quoting and other issues.
  # Special characters have no additional security compared to increasing length.
  special          = false
  override_special = "!#$%^&*()<>-_"

  keepers = {
    cluster_name = var.cluster_name
    db_name      = var.database_name
  }
}


output "database_name" {
  value       = local.database_name
  description = "Postgres database name"
}

output "admin_username" {
  value       = module.aurora_postgres_cluster.master_username
  description = "Postgres admin username"
  sensitive   = true
}

output "master_hostname" {
  value       = module.aurora_postgres_cluster.master_host
  description = "Postgres master hostname"
}

output "replicas_hostname" {
  value       = module.aurora_postgres_cluster.replicas_host
  description = "Postgres replicas hostname"
}

output "cluster_identifier" {
  value       = module.aurora_postgres_cluster.cluster_identifier
  description = "Postgres cluster identifier"
}

output "ssm_key_paths" {
  value       = module.parameter_store_write.names
  description = "Names (key paths) of all SSM parameters stored for this cluster"
}

output "config_map" {
  value = {
    cluster          = module.aurora_postgres_cluster.cluster_identifier
    database         = local.database_name
    hostname         = module.aurora_postgres_cluster.master_host
    port             = var.database_port
    endpoint         = module.aurora_postgres_cluster.endpoint
    username         = module.aurora_postgres_cluster.master_username
    password_ssm_key = local.admin_password_key
  }
  description = "Map containing information pertinent to a PostgreSQL client configuration."
  sensitive   = true
}

output "kms_key_arn" {
  value       = module.kms_key_rds.key_arn
  description = "KMS key ARN for Aurora Postgres"
}

output "allowed_security_groups" {
  value       = local.allowed_security_groups
  description = "The resulting list of security group IDs that are allowed to connect to the Aurora Postgres cluster."
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


module "vpc" {
  source  = "cloudposse/stack-config/yaml//modules/remote-state"
  version = "1.5.0"

  component = var.vpc_component_name

  context = module.cluster.context
}

module "vpc_ingress" {
  source  = "cloudposse/stack-config/yaml//modules/remote-state"
  version = "1.5.0"

  for_each = {
    for i, account in var.allow_ingress_from_vpc_accounts :
    try(account.tenant, module.this.tenant)!= null?
    format("%s-%s", account.tenant, account.stage) : account.stage => account
  }

  component   = each.value.vpc
  tenant      = try(each.value.tenant, module.this.tenant)
  environment = try(each.value.environment, module.this.environment)
  stage       = try(each.value.stage, module.this.stage)

  context = module.cluster.context
}

module "eks" {
  source  = "cloudposse/stack-config/yaml//modules/remote-state"
  version = "1.5.0"

  for_each  = local.eks_security_group_enabled? var.eks_component_names : toset([])
  component = each.value

  context = module.cluster.context
}


module "dns_gbl_delegated" {
  source  = "cloudposse/stack-config/yaml//modules/remote-state"
  version = "1.5.0"

  component   = "dns-delegated"
  environment = var.dns_gbl_delegated_environment_name

  context = module.cluster.context
}


locals {
  ssm_path_prefix = length(var.ssm_cluster_name_override) > 0 ? format("/%s/%s", var.ssm_path_prefix, var.ssm_cluster_name_override) : format("/%s/%s", var.ssm_path_prefix, module.cluster.id)

  admin_user_key     = format("%s/%s/%s", local.ssm_path_prefix, "admin", "user")
  admin_password_key = format("%s/%s/%s", local.ssm_path_prefix, "admin", "password")

  cluster_domain = trimprefix(module.aurora_postgres_cluster.endpoint, "${module.aurora_postgres_cluster.cluster_identifier}.cluster-")

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
      value       = module.aurora_postgres_cluster.master_host
      description = "Aurora Postgres DB Master hostname"
      type        = "String"
      overwrite   = true
    },
    {
      name        = format("%s/%s", local.ssm_path_prefix, "db_port")
      value       = var.database_port
      description = "Aurora Postgres DB Master TCP port"
      type        = "String"
      overwrite   = true
    },
    {
      name        = format("%s/%s", local.ssm_path_prefix, "cluster_name")
      value       = module.aurora_postgres_cluster.cluster_identifier
      description = "Aurora Postgres DB Cluster Identifier"
      type        = "String"
      overwrite   = true
    }
  ]
  cluster_parameters = var.cluster_size > 0? [
    {
      name        = format("%s/%s", local.ssm_path_prefix, "replicas_hostname")
      value       = module.aurora_postgres_cluster.replicas_host
      description = "Aurora Postgres DB Replicas hostname"
      type        = "String"
      overwrite   = true
    },
  ] : []
  admin_user_parameters = [
    {
      name        = local.admin_user_key
      value       = local.admin_user
      description = "Aurora Postgres DB admin user"
      type        = "String"
      overwrite   = true
    },
    {
      name        = local.admin_password_key
      value       = local.admin_password
      description = "Aurora Postgres DB admin password"
      type        = "SecureString"
      overwrite   = true
    }
  ]

  parameter_write = concat(local.default_parameters, local.cluster_parameters, local.admin_user_parameters)
}

module "parameter_store_write" {
  source  = "cloudposse/ssm-parameter-store/aws"
  version = "0.11.0"

  # kms_arn will only be used for SecureString parameters
  kms_arn = module.kms_key_rds.key_arn

  parameter_write = local.parameter_write

  context = module.cluster.context
}


variable "region" {
  type        = string
  description = "AWS Region"
}

variable "dns_gbl_delegated_environment_name" {
  type        = string
  description = "The name of the environment where global `dns_delegated` is provisioned"
  default     = "gbl"
}

variable "cluster_name" {
  type        = string
  description = "Short name for this cluster"
}

variable "database_name" {
  type        = string
  description = "Name for an automatically created database on cluster creation. An empty name will generate a db name."
  default     = ""
}

variable "deletion_protection" {
  type        = bool
  default     = false
  description = "Specifies whether the Cluster should have deletion protection enabled. The database can't be deleted when this value is set to `true`"
}

variable "skip_final_snapshot" {
  type        = bool
  default     = false
  description = <<-EOT
    Normally AWS makes a snapshot of the database before deleting it. Set this to `true` in order to skip this.
    NOTE: The final snapshot has a name derived from the cluster name. If you delete a cluster, get a final snapshot,
    then create a cluster of the same name, its final snapshot will fail with a name collision unless you delete
    the previous final snapshot first.
    EOT
}

variable "storage_encrypted" {
  type        = bool
  default     = true
  description = "Specifies whether the DB cluster is encrypted"
}

variable "engine" {
  type        = string
  description = "Name of the database engine to be used for the DB cluster"
  default     = "postgresql"
}

variable "engine_version" {
  type        = string
  description = "Engine version of the Aurora global database"
  default     = "13.4"
}

variable "allow_major_version_upgrade" {
  type        = bool
  default     = false
  description = "Enable to allow major engine version upgrades when changing engine versions. Defaults to false."
}

variable "ca_cert_identifier" {
  description = "The identifier of the CA certificate for the DB instance"
  type        = string
  default     = null
}

variable "engine_mode" {
  type        = string
  description = "The database engine mode. Valid values: `global`, `multimaster`, `parallelquery`, `provisioned`, `serverless`"
}

variable "cluster_family" {
  type        = string
  description = "Family of the DB parameter group. Valid values for Aurora PostgreSQL: `aurora-postgresql9.6`, `aurora-postgresql10`, `aurora-postgresql11`, `aurora-postgresql12`"
  default     = "aurora-postgresql13"
}

variable "database_port" {
  type        = number
  description = "Database port"
  default     = 5432
}

# Don't use `admin`
# Read more: <https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/CHAP_Limits.html>
# ("MasterUsername admin cannot be used as it is a reserved word used by the engine")
variable "admin_user" {
  type        = string
  description = "Postgres admin user name"
  default     = ""

  validation {
    condition = (
      length(var.admin_user) == 0 ||
      (var.admin_user!= "admin" &&
        length(var.admin_user) >= 1 &&
      length(var.admin_user) <= 16)
    )
    error_message = "Per the RDS API, admin cannot be used as it is a reserved word used by the engine. Master username must be between 1 and 16 characters. If an empty string is provided then a random string will be used."
  }
}

# Must be longer than 8 chars
# Read more: <https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/CHAP_Limits.html>
# ("The parameter MasterUserPassword is not a valid password because it is shorter than 8 characters")
variable "admin_password" {
  type        = string
  description = "Postgres password for the admin user"
  default     = ""
  sensitive   = true

  validation {
    condition = (
      length(var.admin_password) == 0 ||
      (length(var.admin_password) >= 8 &&
      length(var.admin_password) <= 128)
    )
    error_message = "Per the RDS API, master password must be between 8 and 128 characters. If an empty string is provided then a random password will be used."
  }
}

# https://aws.amazon.com/rds/aurora/pricing
variable "instance_type" {
  type        = string
  description = "EC2 instance type for Postgres cluster"
}

variable "cluster_size" {
  type        = number
  description = "Postgres cluster size"
}

variable "iam_database_authentication_enabled" {
  type        = bool
  description = "Specifies whether or mappings of AWS Identity and Access Management (IAM) accounts to database accounts is enabled"
  default     = false
}

variable "cluster_dns_name_part" {
  type        = string
  description = "Part of DNS name added to module and cluster name for DNS for cluster endpoint"
  default     = "writer"
}

variable "reader_dns_name_part" {
  type        = string
  description = "Part of DNS name added to module and cluster name for DNS for cluster reader"
  default     = "reader"
}

variable "ssm_path_prefix" {
  type        = string
  default     = "aurora-postgres"
  description = "Top level SSM path prefix (without leading or trailing slash)"
}

variable "publicly_accessible" {
  type        = bool
  description = "Set true to make this database accessible from the public internet"
  default     = false
}

variable "allowed_cidr_blocks" {
  type        = list(string)
  description = "List of CIDRs allowed to access the database (in addition to security groups and subnets)"
  default     = []
}

variable "maintenance_window" {
  type        = string
  default     = "wed:03:00-wed:04:00"
  description = "Weekly time range during which system maintenance can occur, in UTC"
}

variable "enabled_cloudwatch_logs_exports" {
  type        = list(string)
  description = "List of log types to export to cloudwatch. The following log types are supported: audit, error, general, slowquery"
  default     = []
}

variable "performance_insights_enabled" {
  type        = bool
  default     = true
  description = "Whether to enable Performance Insights"
}

variable "enhanced_monitoring_role_enabled" {
  type        = bool
  description = "A boolean flag to enable/disable the creation of the enhanced monitoring IAM role. If set to `false`, the module will not create a new role and will use `rds_monitoring_role_arn` for enhanced monitoring"
  default     = true
}

variable "enhanced_monitoring_attributes" {
  type        = list(string)
  description = "Attributes used to format the Enhanced Monitoring IAM role. If this role hits IAM role length restrictions (max 64 characters), consider shortening these strings."
  default     = ["enhanced-monitoring"]
}

variable "rds_monitoring_interval" {
  type        = number
  description = "The interval, in seconds, between points when enhanced monitoring metrics are collected for the DB instance. To disable collecting Enhanced Monitoring metrics, specify 0. The default is 0. Valid Values: 0, 1, 5, 10, 15, 30, 60"
  default     = 60
}

variable "autoscaling_enabled" {
  type        = bool
  default     = false
  description = "Whether to enable cluster autoscaling"
}

variable "autoscaling_policy_type" {
  type        = string
  default     = "TargetTrackingScaling"
  description = "Autoscaling policy type. `TargetTrackingScaling` and `StepScaling` are supported"
}

variable "autoscaling_target_metrics" {
  type        = string
  default     = "RDSReaderAverageCPUUtilization"
  description = "The metrics type to use. If this value isn't provided the default is CPU utilization"
}

variable "autoscaling_target_value" {
  type        = number
  default     = 75
  description = "The target value to scale with respect to target metrics"
}

variable "autoscaling_scale_in_cooldown" {
  type        = number
  default     = 300
  description = "The amount of time, in seconds, after a scaling activity completes and before the next scaling down activity can start. Default is 300s"
}

variable "autoscaling_scale_out_cooldown" {
  type        = number
  default     = 300
  description = "The amount of time, in seconds, after a scaling activity completes and before the next scaling up activity can start. Default is 300s"
}

variable "autoscaling_min_capacity" {
  type        = number
  default     = 1
  description = "Minimum number of instances to be maintained by the autoscaler"
}

variable "autoscaling_max_capacity" {
  type        = number
  default     = 5
  description = "Maximum number of instances to be maintained by the autoscaler"
}

variable "snapshot_identifier" {
  type        = string
  default     = null
  description = "Specifies whether or not to create this cluster from a snapshot"
}

variable "allowed_security_group_names" {
  type        = list(string)
  description = "List of security group names (tags) that should be allowed access to the database"
  default     = []
}

variable "eks_security_group_enabled" {
  type        = bool
  description = "Use the eks default security group"
  default     = false
}

variable "eks_component_names" {
  type        = set(string)
  description = "The names of the eks components"
  default     = ["eks/cluster"]
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

variable "scaling_configuration" {
  type = list(object({
    auto_pause               = bool
    max_capacity             = number
    min_capacity             = number
    seconds_until_auto_pause = number
    timeout_action           = string
  }))
  default     = []
  description = "List of nested attributes with scaling properties. Only valid when `engine_mode` is set to `serverless`. This is required for Serverless v1"
}

variable "serverlessv2_scaling_configuration" {
  type = object({
    min_capacity = number
    max_capacity = number
  })
  default     = null
  description = "Nested attribute with scaling properties for ServerlessV2. Only valid when `engine_mode` is set to `provisioned.` This is required for Serverless v2"
}

variable "intra_security_group_traffic_enabled" {
  type        = bool
  default     = false
  description = "Whether to allow traffic between resources inside the database's security group."
}

variable "cluster_parameters" {
  type = list(object({
    apply_method = string
    name         = string
    value        = string
  }))
  default     = []
  description = "List of DB cluster parameters to apply"
}

variable "retention_period" {
  type        = number
  default     = 5
  description = "Number of days to retain backups for"
}

variable "backup_window" {
  type        = string
  default     = "07:00-09:00"
  description = "Daily time range during which the backups happen, UTC"
}

variable "ssm_cluster_name_override" {
  type        = string
  default     = ""
  description = "Set a cluster name into the ssm path prefix"
}


terraform {
  required_version = ">= 1.3.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 4.9.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 2.3"
    }
    postgresql = {
      source  = "cyrilgdn/postgresql"
      version = ">