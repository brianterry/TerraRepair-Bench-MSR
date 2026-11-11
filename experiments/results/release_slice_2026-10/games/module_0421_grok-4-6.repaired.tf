# A child module automatically inherits default (un-aliased) provider configurations from its parent.
# This means that explicit provider blocks appear only in the root module, and downstream modules can simply
# declare resources for that provider and have them automatically associated with the root provider configurations

# https://www.terraform.io/docs/providers/aws/r/rds_cluster.html
module "aurora_postgres_cluster" {
  source = "git::https://github.com/cloudposse/terraform-aws-rds-cluster.git?ref=5e1d231af7e30fb8dca3c848439ffbadc8759091"

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
  kms_key_arn                          = var.storage_encrypted ? module.kms_key_rds.key_arn : null
  performance_insights_kms_key_id      = module.kms_key_rds.key_arn
  maintenance_window                   = var.maintenance_window
  enabled_cloudwatch_logs_exports      = var.enabled_cloudwatch_logs_exports
  enhanced_monitoring_role_enabled     = var.enhanced_monitoring_role_enabled
  enhanced_monitoring_attributes       = var.enhanced_monitoring_attributes
  performance_insights_enabled         = true
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
  deletion_protection                  = true
  snapshot_identifier                  = var.snapshot_identifier
  allow_major_version_upgrade          = var.allow_major_version_upgrade
  ca_cert_identifier                   = var.ca_cert_identifier
  retention_period                     = var.retention_period
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
# for example `context = module.this.context`,
# and access individual variables as `module.this.<var>`,
# with final values filled in.
#
# For example, when using defaults, `module.this.context.delimiter`
# will be null, and `module.this.delimiter` will be `-` (hyphen).
#

module "this" {
  source = "git::https://github.com/cloudposse/terraform-null-label.git?ref=488ab91e34a24a86957e397d9f7262ec5925586a"

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
      The value of the `name` tag, if included,