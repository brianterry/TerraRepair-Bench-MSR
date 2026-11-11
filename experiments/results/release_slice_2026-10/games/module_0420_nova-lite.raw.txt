```hcl
module "aurora_mysql" {
  source  = "cloudposse/rds-cluster/aws"
  version = "1.3.1"

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

  vpc_id              = local.vpc_id
  publicly_accessible = var.publicly_accessible
  subnets             = var.publicly_accessible? local.public_subnet_ids : local.private_subnet_ids
  allowed_cidr_blocks = local.allowed_cidr_blocks
  security_groups     = local.eks_cluster_managed_security_group_ids

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
  kms_key_arn                     = var.mysql_storage_encrypted? local.kms_key_arn : null
  performance_insights_enabled    = var.performance_insights_enabled
  performance_insights_kms_key_id = var.performance_insights_enabled? local.kms_key_arn : null

  replication_source_identifier = local.replication_source_identifier

  context = module.this.context
}

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

module "kms_key_rds" {
  source  = "cloudposse/kms-key/aws"
  version = "0.12.1"

  description             = "KMS key for Aurora MySQL"
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

data "aws_iam_policy_document" "kms_key_rds" {
  count = local.enabled? 1 : 0

  statement {
    sid    = "Enable the account that owns the KMS key to manage it via IAM"
    effect = "Allow"

    actions = [
      "kms:CreateKey",
      "kms:DescribeKey",
      "kms:ListKeys",
      "kms:ListAliases"
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

  is_read_replica             = local.enabled && var.is_read_replica
  remote_read_replica_enabled = local.is_read_replica &&!(length(var.replication_source_identifier) > 0) && length(var.primary_cluster_region) > 0

  replication_source_identifier = local.remote_read_replica_enabled &&!var.is_promoted_read_replica? module.primary_cluster[0].outputs.aurora_mysql_cluster_arn : var.replication_source_identifier

  kms_key_arn = module.kms_key_rds.key_arn

  mysql_db_enabled     = local.enabled &&!local.is_read_replica
  mysql_db_name        = length(var.mysql_db_name) > 0? var.mysql_db_name : join("", random_pet.mysql_db_name.*.id)
  mysql_admin_user     = length(var.mysql_admin_user) > 0? var.mysql_admin_user : join("", random_pet.mysql_admin_user.*.id)
  fetch_admin_password = local.mysql_db_enabled && length(var.ssm_password_source) > 0
  mysql_admin_password = local.fetch_admin_password? data.aws_ssm_parameter.password[0].value : (
    length(var.mysql_admin_password) > 0? var.mysql_admin_password : join("", random_password.mysql_admin_password.*.result)
  )

  cluster_domain    = trimprefix(module.aurora_mysql.endpoint, "${module.aurora_mysql.cluster_identifier}.cluster-")
  cluster_subdomain = var.mysql_name == ""? module.this.name : "${var.mysql_name}.${module.this.name}"

  all_allowed_cidr_blocks = concat(
    var.allowed_cidr_blocks,
    [
      for k in keys(module.vpc_ingress) :
      module.vpc_ingress[k].outputs.vpc_cidr
    ]
  )
  allowed_cidr_blocks = var.publicly_accessible? coalescelist(local.all_allowed_cidr_blocks, ["0.0.0.0/0"]) : local.all_allowed_cidr_blocks
}

module "cluster" {
  source  = "cloudposse/label/null"
  version = "0.25.0"

  attributes = [var.mysql_name]

  context = module.this.context
}

resource "random_pet" "mysql_admin_user" {
  count     = local.mysql_db_enabled && length(var.mysql_admin_user) == 0? 1 : 0
  length    = 2
  separator = "_"
}

resource "random_password" "mysql_admin_password" {
  count   = local.mysql_db_enabled && length(var.mysql_admin_password) == 0 && local.fetch_admin_password == false? 1 : 0
  length  = 33
  special = false
}

resource "random_pet" "mysql_db_name" {
  count = local.mysql_db_enabled && length(var.mysql_db_name) == 0? 1 : 0

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
  value       = local.enabled? module.aurora_mysql.cluster_identifier : null
  description = "Aurora MySQL cluster identifier"
}

output "aurora_mysql_endpoint" {
  value       = local.enabled? module.aurora_mysql.endpoint : null
  description = "Aurora MySQL endpoint"
}

output "aurora_mysql_master_hostname" {
  value       = local.enabled? module.aurora_mysql.master_host : null
  description = "Aurora MySQL DB master hostname"
}

output "aurora_mysql_master_password" {
  value       = local.mysql_db_enabled? "Password for admin user ${module.aurora_mysql.master_username} is stored in SSM at ${local.mysql_admin_password_key}" : null
  description = "Location of admin password in SSM"
  sensitive   = true
}

output "aurora_mysql_master_password_ssm_key" {
  value       = local.mysql_db_enabled? local.mysql_admin_password_key : null
  description = "SSM key for admin password"
}

output "aurora_mysql_master_username" {
  value       = local.enabled? module.aurora_mysql.master_username : null
  description = "Aurora MySQL username for the master DB user"
  sensitive   = true
}

output "aurora_mysql_reader_endpoint" {
  value       = local.enabled? module.aurora_mysql.reader_endpoint : null
  description = "Aurora MySQL reader endpoint"
}

output "aurora_mysql_replicas_hostname" {
  value       = local.enabled? module.aurora_mysql.replicas_host : null
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

locals {
  accounts_with_vpc = { for i, account in var.allow_ingress_from_vpc_accounts : try(account.tenant, module.this.tenant)!= null? format("%s-%s", account.tenant, account.stage) : account.stage => account }
}

module "dns-delegated" {
  source  = "cloudposse/stack-config/yaml//modules/remote-state@sha256:458468576487654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654654