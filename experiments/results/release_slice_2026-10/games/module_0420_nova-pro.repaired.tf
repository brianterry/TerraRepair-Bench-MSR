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
  performance_insights_enabled    = true
  performance_insights_kms_key_id = local.kms_key_arn

  replication_source_identifier = local.replication_source_identifier

  context = module.this.context
}

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
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:Describe*",
      "kms:CreateGrant"
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
      "kms:Encrypt",
      "kms:Decrypt",
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

module "cluster" {
  source  = "cloudposse/label/null"
  version = "0.25.0"

  attributes = [var.mysql_name]

  context = module.this.context
}

module "dns-delegated" {
  source  = "cloudposse/stack-config/yaml//modules/remote-state"
  version = "1.5.0"

  component   = "dns-delegated"
  environment = "gbl"

  context = module.this.context
}

module "eks" {
  source  = "cloudposse/stack-config/yaml//modules/remote-state"
  version = "1.5.0"

  for_each = var.eks_component_names

  component = each.value

  context = module.this.context
}

module "vpc" {
  source  = "cloudposse/stack-config/yaml//modules/remote-state"
  version = "1.5.0"

  component = var.vpc_component_name

  context = module.this.context
}

module "vpc_ingress" {
  source  = "cloudposse/stack-config/yaml//modules/remote-state"
  version = "1.5.0"

  for_each = local.accounts_with_vpc

  component   = each.value.vpc
  environment = try(each.value.environment, module.this.environment)
  stage       = try(each.value.stage, module.this.environment)
  tenant      = try(each.value.tenant, module.this.tenant)

  context = module.this.context
}

module "primary_cluster" {
  source  = "cloudposse/stack-config/yaml//modules/remote-state"
  version = "1.5.0"

  count = local.remote_read_replica_enabled? 1 : 0

  component   = var.primary_cluster_component
  environment = var.primary_cluster_region

  context = module.this.context
}

module "parameter_store_write" {
  source  = "cloudposse/ssm-parameter-store/aws"
  version = "0.11.0"

  kms_arn = module.kms_key_rds.key_arn

  parameter_write = local.parameter_write

  context = module.cluster.context
}