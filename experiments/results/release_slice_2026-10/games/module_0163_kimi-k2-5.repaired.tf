locals {
  monitoring_role_arn = var.create_monitoring_role ? aws_iam_role.enhanced_monitoring[0].arn : var.monitoring_role_arn

  final_snapshot_identifier = var.skip_final_snapshot ? null : "${var.final_snapshot_identifier_prefix}-${var.identifier}-${try(random_id.snapshot_identifier[0].hex, "")}"

  identifier        = var.use_identifier_prefix ? null : var.identifier
  identifier_prefix = var.use_identifier_prefix ? "${var.identifier}-" : null

  monitoring_role_name        = var.monitoring_role_use_name_prefix ? null : var.monitoring_role_name
  monitoring_role_name_prefix = var.monitoring_role_use_name_prefix ? "${var.monitoring_role_name}-" : null

  # Replicas will use source metadata
  is_replica = var.replicate_source_db != null
}

# Ref. https://docs.aws.amazon.com/general/latest/gr/aws-arns-and-namespaces.html#genref-aws-service-namespaces
data "aws_partition" "current" {}

resource "random_id" "snapshot_identifier" {
  count = var.create && !var.skip_final_snapshot ? 1 : 0

  keepers = {
    id                  = var.identifier
    snapshot_identifier = var.snapshot_identifier
  }

  byte_length = 4
}

resource "aws_db_instance" "this" {
  count = var.create ? 1 : 0

  identifier        = local.identifier
  identifier_prefix = local.identifier_prefix

  engine                   = local.is_replica ? null : var.engine
  engine_version           = var.engine_version
  engine_lifecycle_support = var.engine_lifecycle_support
  instance_class           = var.instance_class
  allocated_storage        = var.allocated_storage
  storage_type             = var.storage_type
  storage_encrypted        = var.storage_encrypted
  kms_key_id               = var.kms_key_id
  license_model            = var.license_model

  db_name                             = var.db_name
  username                            = !local.is_replica ? var.username : null
  password_wo                         = !local.is_replica && var.manage_master_user_password ? null : var.password_wo
  password_wo_version                 = !local.is_replica && var.manage_master_user_password ? null : var.password_wo_version
  port                                = var.port
  domain                              = var.domain
  domain_auth_secret_arn              = var.domain_auth_secret_arn
  domain_dns_ips                      = var.domain_dns_ips
  domain_fqdn                         = var.domain_fqdn
  domain_iam_role_name                = var.domain_iam_role_name
  domain_ou                           = var.domain_ou
  iam_database_authentication_enabled = var.iam_database_authentication_enabled
  custom_iam_instance_profile         = var.custom_iam_instance_profile
  manage_master_user_password         = !local.is_replica && var.manage_master_user_password ? var.manage_master_user_password : null
  master_user_secret_kms_key_id       = !local.is_replica && var.manage_master_user_password ? var.master_user_secret_kms_key_id : null

  vpc_security_group_ids = var.vpc_security_group_ids
  db_subnet_group_name   = var.db_subnet_group_name
  parameter_group_name   = var.parameter_group_name
  option_group_name      = var.option_group_name
  network_type           = var.network_type

  availability_zone      = var.availability_zone
  multi_az               = true
  iops                   = var.iops
  storage_throughput     = var.storage_throughput
  publicly_accessible    = var.publicly_accessible
  ca_cert_identifier     = var.ca_cert_identifier
  dedicated_log_volume   = var.dedicated_log_volume
  upgrade_storage_config = var.upgrade_storage_config

  allow_major_version_upgrade = var.allow_major_version_upgrade
  auto_minor_version_upgrade  = var.auto_minor_version_upgrade
  apply_immediately           = var.apply_immediately
  maintenance_window          = var.maintenance_window

  # https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/blue-green-deployments.html
  dynamic "blue_green_update" {
    for_each = var.blue_green_update != null ? [var.blue_green_update] : []

    content {
      enabled = blue_green_update.value.enabled
    }
  }

  snapshot_identifier       = var.snapshot_identifier
  copy_tags_to_snapshot     = var.copy_tags_to_snapshot
  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = local.final_snapshot_identifier

  performance_insights_enabled          = true
  performance_insights_retention_period = var.performance_insights_retention_period
  performance_insights_kms_key_id       = var.performance_insights_kms_key_id

  replicate_source_db     = var.replicate_source_db
  replica_mode            = var.replica_mode
  backup_retention_period = var.blue_green_update != null ? coalesce(var.backup_retention_period, 1) : coalesce(var.backup_retention_period, 7)
  backup_window           = var.backup_window
  max_allocated_storage   = var.max_allocated_storage
  monitoring_interval     = 60
  monitoring_role_arn     = local.monitoring_role_arn
  database_insights_mode  = var.database_insights_mode

  character_set_name              = var.character_set_name
  nchar_character_set_name        = var.nchar_character_set_name
  timezone                        = var.timezone
  enabled_cloudwatch_logs_exports = length(var.enabled_cloudwatch_logs_exports) > 0 ? var.enabled_cloudwatch_logs_exports : ["error", "general", "slowquery"]

  deletion_protection      = true
  delete_automated_backups = var.delete_automated_backups

  region = var.region

  dynamic "restore_to_point_in_time" {
    for_each = var.restore_to_point_in_time != null ? [var.restore_to_point_in_time] : []

    content {
      restore_time                             = restore_to_point_in_time.value.restore_time
      source_db_instance_automated_backups_arn = restore_to_point_in_time.value.source_db_instance_automated_backups_arn
      source_db_instance_identifier            = restore_to_point_in_time.value.source_db_instance_identifier
      source_dbi_resource_id                   = restore_to_point_in_time.value.source_dbi_resource_id
      use_latest_restorable_time               = restore_to_point_in_time.value.use_latest_restorable_time
    }
  }

  dynamic "s3_import" {
    for_each = var.s3_import != null ? [var.s3_import] : []

    content {
      source_engine         = "mysql"
      source_engine_version = s3_import.value.source_engine_version
      bucket_name           = s3_import.value.bucket_name
      bucket_prefix         = s3_import.value.bucket_prefix
      ingestion_role        = s3_import.value.ingestion_role
    }
  }

  tags = merge(var.tags, var.db_instance_tags)

  depends_on = [aws_cloudwatch_log_group.this]

  dynamic "timeouts" {
    for_each = var.timeouts != null ? [var.timeouts] : []

    content {
      create = timeouts.value.create
      update = timeouts.value.update
      delete = timeouts.value.delete
    }
  }

  # Note: do not add `latest_restorable_time` to `ignore_changes`
  # https://github.com/terraform-aws-modules/terraform-aws-rds/issues/478
}

################################################################################
# CloudWatch Log Group
################################################################################

# Log groups will not be created if using an identifier prefix
resource "aws_cloudwatch_log_group" "this" {
  for_each = toset([for log in var.enabled_cloudwatch_logs_exports : log if var.create && var.create_cloudwatch_log_group && !var.use_identifier_prefix])

  name              = "/aws/rds/instance/${var.identifier}/${each.value}"
  retention_in_days = 365
  kms_key_id        = var.cloudwatch_log_group_kms_key_id
  skip_destroy      = var.cloudwatch_log_group_skip_destroy
  log_group_class   = var.cloudwatch_log_group_class
  region            = var.region

  tags = merge(var.tags, var.cloudwatch_log_group_tags)
}

################################################################################
# Enhanced monitoring
################################################################################

data "aws_iam_policy_document" "enhanced_monitoring" {
  statement {
    actions = [
      "sts:AssumeRole",
    ]

    principals {
      type        = "Service"
      identifiers = ["monitoring.rds.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "enhanced_monitoring" {
  count = var.create_monitoring_role ? 1 : 0

  name                 = local.monitoring_role_name
  name_prefix          = local.monitoring_role_name_prefix
  assume_role_policy   = data.aws_iam_policy_document.enhanced_monitoring.json
  description          = var.monitoring_role_description
  permissions_boundary = var.monitoring_role_permissions_boundary

  tags = merge(
    {
      "Name" = format("%s", var.monitoring_role_name)
    },
    var.tags,
  )
}

resource "aws_iam_role_policy_attachment" "enhanced_monitoring" {
  count = var.create_monitoring_role ? 1 : 0

  role       = aws_iam_role.enhanced_monitoring[0].name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

################################################################################
# Managed Secret Rotation
################################################################################

# There is not currently a way to disable secret rotation on an initial apply.
# In order to use master password secrets management without a rotation, the following workaround can be used:
# `manage_master_user_password_rotation` must be set to true first and applied followed by setting it to false and another apply.
# Note: when setting `manage_master_user_password_rotation` to true, a schedule must also be set using `master_user_password_rotation_schedule_expression` or `master_user_password_rotation_automatically_after_days`.
# See: https://github.com/hashicorp/terraform-provider-aws/issues/37779
resource "aws_secretsmanager_secret_rotation" "this" {
  count = var.create && var.manage_master_user_password && var.manage_master_user_password_rotation ? 1 : 0

  secret_id          = aws_db_instance.this[0].master_user_secret[0].secret_arn
  rotate_immediately = var.master_user_password_rotate_immediately
  region             = var.region

  rotation_rules {
    automatically_after_days = coalesce(var.master_user_password_rotation_automatically_after_days, 90)
    duration                 = var.master_user_password_rotation_duration
    schedule_expression      = var.master_user_password_rotation_schedule_expression
  }
}


output "enhanced_monitoring_iam_role_name" {
  description = "The name of the monitoring role"
  value       = try(aws_iam_role.enhanced_monitoring[0].name, null)
}

output "enhanced_monitoring_iam_role_arn" {
  description = "The Amazon Resource Name (ARN) specifying the monitoring role"
  value       = try(aws_iam_role.enhanced_monitoring[0].arn, null)
}

output "db_instance_address" {
  description = "The address of the RDS instance"
  value       = try(aws_db_instance.this[0].address, null)
}

output "db_instance_arn" {
  description = "The ARN of the RDS instance"
  value       = try(aws_db_instance.this[0].arn, null)
}

output "db_instance_availability_zone" {
  description = "The availability zone of the RDS instance"
  value       = try(aws_db_instance.this[0].availability_zone, null)
}

output "db_instance_endpoint" {
  description = "The connection endpoint"
  value       = try(aws_db_instance.this[0].endpoint, null)
}

output "db_listener_endpoint" {
  description = "Specifies the listener connection endpoint for SQL Server Always On"
  value       = try(aws_db_instance.this[0].listener_endpoint, null)
}

output "db_instance_engine" {
  description = "The database engine"
  value       = try(aws_db_instance.this[0].engine, null)
}

output "db_instance_engine_version_actual" {
  description = "The running version of the database"
  value       = try(aws_db_instance.this[0].engine_version_actual, null)
}

output "db_instance_hosted_zone_id" {
  description = "The canonical hosted zone ID of the DB instance (to be used in a Route 53 Alias record)"
  value       = try(aws_db_instance.this[0].hosted_zone_id, null)
}

output "db_instance_identifier" {
  description = "The RDS instance identifier"
  value       = try(aws_db_instance.this[0].identifier, null)
}

output "db_instance_resource_id" {
  description = "The RDS Resource ID of this instance"
  value       = try(aws_db_instance.this[0].resource_id, null)
}

output "db_instance_status" {
  description = "The RDS instance status"
  value       = try(aws_db_instance.this[0].status, null)
}

output "db_instance_name" {
  description = "The database name"
  value       = try(aws_db_instance.this[0].db_name, null)
}

output "db_instance_username" {
  description = "The master username for the database"
  value       = try(aws_db_instance.this[0].username, null)
  sensitive   = true
}

output "db_instance_port" {
  description = "The database port"
  value       = try(aws_db_instance.this[0].port, null)
}

output "db_instance_ca_cert_identifier" {
  description = "Specifies the identifier of the CA certificate for the DB instance"
  value       = try(aws_db_instance.this[0].ca_cert_identifier, null)
}

output "db_instance_domain" {
  description = "The ID of the Directory Service Active Directory domain the instance is joined to"
  value       = try(aws_db_instance.this[0].domain, null)
}

output "db_instance_domain_auth_secret_arn" {
  description = "The ARN for the Secrets Manager secret with the self managed Active Directory credentials for the user joining the domain"
  value       = try(aws_db_instance.this[0].domain_auth_secret_arn, null)
}

output "db_instance_domain_dns_ips" {
  description = "The IPv4 DNS IP addresses of your primary and secondary self managed Active Directory domain controllers"
  value       = try(aws_db_instance.this[0].domain_dns_ips, null)
}

output "db_instance_domain_fqdn" {
  description = "The fully qualified domain name (FQDN) of an self managed Active Directory domain"
  value       = try(aws_db_instance.this[0].domain_fqdn, null)
}

output "db_instance_domain_iam_role_name" {
  description = "The name of the IAM role to be used when making API calls to the Directory Service"
  value       = try(aws_db_instance.this[0].domain_iam_role_name, null)
}

output "db_instance_domain_ou" {
  description = "The self managed Active Directory organizational unit for your DB instance to join"
  value       = try(aws_db_instance.this[0].domain_ou, null)
}

output "db_instance_master_user_secret_arn" {
  description = "The ARN of the master user secret (Only available when manage_master_user_password is set to true)"
  value       = try(aws_db_instance.this[0].master_user_secret[0].secret_arn, null)
}

output "db_instance_upgrade_rollout_order" {
  description = "Order in which the instances are upgraded (first, second, last)"
  value       = try(aws_db_instance.this[0].upgrade_rollout_order, null)
}

################################################################################
# CloudWatch Log Group
################################################################################

output "db_instance_cloudwatch_log_groups" {
  description = "Map of CloudWatch log groups created and their attributes"
  value       = aws_cloudwatch_log_group.this
}

################################################################################
# Managed Secret Rotation
################################################################################

output "db_instance_secretsmanager_secret_rotation_enabled" {
  description = "Specifies whether automatic rotation is enabled for the secret"
  value       = try(aws_secretsmanager_secret_rotation.this[0].rotation_enabled, null)
}


variable "create" {
  description = "Whether to create this resource or not?"
  type        = bool
  default     = true
}

variable "region" {
  description = "Region where this resource will be managed. Defaults to the Region set in the provider configuration"
  type        = string
  default     = null
}

variable "identifier" {
  description = "The name of the RDS instance"
  type        = string
}
variable "custom_iam_instance_profile" {
  description = "RDS custom iam instance profile"
  type        = string
  default     = null
}

variable "use_identifier_prefix" {
  description = "Determines whether to use `identifier` as is or create a unique identifier beginning with `identifier` as the specified prefix"
  type        = bool
  default     = false
}

variable "allocated_storage" {
  description = "The allocated storage in gigabytes"
  type        = number
  default     = null
}

variable "storage_type" {
  description = "One of 'standard' (magnetic), 'gp2' (general purpose SSD), 'gp3' (new generation of general purpose SSD), or 'io1' (provisioned IOPS SSD). The default is 'io1' if iops is specified, 'gp2' if not. If you specify 'io1' or 'gp3' , you must also include a value for the 'iops' parameter"
  type        = string
  default     = null
}

variable "storage_throughput" {
  description = "Storage throughput value for the DB instance. This setting applies only to the `gp3` storage type. See `notes` for limitations regarding this variable for `gp3`"
  type        = number
  default     = null
}

variable "storage_encrypted" {
  description = "Specifies whether the DB instance is encrypted"
  type        = bool
  default     = true
}

variable "kms_key_id" {
  description = "The ARN for the KMS encryption key. If creating an encrypted replica, set this to the destination KMS ARN. If storage_encrypted is set to true and kms_key_id is not specified the default KMS key created in your account will be used"
  type        = string
  default     = null
}

variable "replicate_source_db" {
  description = "Specifies that this resource is a Replicate database, and to use this value as the source database. This correlates to the identifier of another Amazon RDS Database to replicate."
  type        = string
  default     = null
}

variable "license_model" {
  description = "License model information for this DB instance. Optional, but required for some DB engines, i.e. Oracle SE1"
  type        = string
  default     = null
}

variable "replica_mode" {
  description = "Specifies whether the replica is in either mounted or open-read-only mode. This attribute is only supported by Oracle instances. Oracle replicas operate in open-read-only mode unless otherwise specified"
  type        = string
  default     = null
}

variable "iam_database_authentication_enabled" {
  description = "Specifies whether or mappings of AWS Identity and Access Management (IAM) accounts to database accounts is enabled"
  type        = bool
  default     = false
}

variable "domain" {
  description = "The ID of the Directory Service Active Directory domain to create the instance in"
  type        = string
  default     = null
}

variable "domain_auth_secret_arn" {
  description = "(Optional, but required if domain_fqdn is provided) The ARN for the Secrets Manager secret with the self managed Active Directory credentials for the user joining the domain. Conflicts with domain and domain_iam_role_name."
  type        = string
  default     = null
}

variable "domain_dns_ips" {
  description = "(Optional, but required if domain_fqdn is provided) The IPv4 DNS IP addresses of your primary and secondary self managed Active Directory domain controllers. Two IP addresses must be provided. If there isn't a secondary domain controller, use the IP address of the primary domain controller for both entries in the list. Conflicts with domain and domain_iam_role_name."
  type        = list(string)
  default     = null
}

variable "domain_fqdn" {
  description = "The fully qualified domain name (FQDN) of the self managed Active Directory domain. Conflicts with domain and domain_iam_role_name."
  type        = string
  default     = null
}

variable "domain_iam_role_name" {
  description = "(Required if domain is provided) The name of the IAM role to be used when making API calls to the Directory Service"
  type        = string
  default     = null
}

variable "domain_ou" {
  description = "(Optional, but required if domain_fqdn is provided) The self managed Active Directory organizational unit for your DB instance to join. Conflicts with domain and domain_iam_role_name."
  type        = string
  default     = null
}

variable "engine" {
  description = "The database engine to use"
  type        = string
  default     = null
}

variable "engine_version" {
  description = "The engine version to use"
  type        = string
  default     = null
}

variable "engine_lifecycle_support" {
  description = "The life cycle type for this DB instance. This setting applies only to RDS for MySQL and RDS for PostgreSQL. Valid values are `open-source-rds-extended-support`, `open-source-rds-extended-support-disabled`. Default value is `open-source-rds-extended-support`."
  type        = string
  default     = null
}

variable "instance_class" {
  description = "The instance type of the RDS instance"
  type        = string
  default     = null
}

variable "db_name" {
  description = "The DB name to create. If omitted, no database is created initially"
  type        = string
  default     = null
}

variable "username" {
  description = "Username for the master DB user"
  type        = string
  default     = null
}

variable "password_wo" {
  description = "Write-Only required unless `manage_master_user_password` is set to `true`, `snapshot_identifier`, or `replicate_source_db` is provided). Password for the master DB user. Note that this may show up in logs, and it will be stored in the state file"
  type        = string
  sensitive   = true
  ephemeral   = true
  default     = null
}

variable "password_wo_version" {
  description = "Used together with password_wo to trigger an update. Increment this value when an update to password_wo is required."
  type        = number
  default     = null
}

variable "manage_master_user_password" {
  description = "Set to true to allow RDS to manage the master user password in Secrets Manager. Cannot be set if password is provided"
  type        = bool
  default     = true
}

variable "master_user_secret_kms_key_id" {
  description = <<EOF
  The key ARN, key ID, alias ARN or alias name for the KMS key to encrypt the master user password secret in Secrets Manager.
  If not specified, the default KMS key for your Amazon Web Services account is used.
  EOF
  type        = string
  default     = null
}

variable "port" {
  description = "The port on which the DB accepts connections"
  type        = string
  default     = null
}

variable "skip_final_snapshot" {
  description = "Determines whether a final DB snapshot is created before the DB instance is deleted. If true is specified, no DBSnapshot is created. If false is specified, a DB snapshot is created before the DB instance is deleted"
  type        = bool
  default     = false
}

variable "snapshot_identifier" {
  description = "Specifies whether or not to create this database from a snapshot. This correlates to the snapshot ID you'd find in the RDS console, e.g: rds:production-2015-06-26-06-05."
  type        = string
  default     = null
}

variable "copy_tags_to_snapshot" {
  description = "On delete, copy all Instance tags to the final snapshot"
  type        = bool
  default     = true
}

variable "final_snapshot_identifier_prefix" {
  description = "The name which is prefixed to the final snapshot on cluster destroy"
  type        = string
  default     = "final"
}

variable "vpc_security_group_ids" {
  description = "List of VPC security groups to associate"
  type        = list(string)
  default     = []
}

variable "db_subnet_group_name" {
  description = "Name of DB subnet group. DB instance will be created in the VPC associated with the DB subnet group. If unspecified, will be created in the default VPC"
  type        = string
  default     = null
}

variable "parameter_group_name" {
  description = "Name of the DB parameter group to associate"
  type        = string
  default     = null
}

variable "availability_zone" {
  description = "The Availability Zone of the RDS instance"
  type        = string
  default     = null
}

variable "multi_az" {
  description = "Specifies if the RDS instance is multi-AZ"
  type        = bool
  default     = false
}

variable "iops" {
  description = "The amount of provisioned IOPS. Setting this implies a storage_type of 'io1' or `gp3`. See `notes` for limitations regarding this variable for `gp3`"
  type        = number
  default     = null
}

variable "publicly_accessible" {
  description = "Bool to control if instance is publicly accessible"
  type        = bool
  default     = false
}

variable "monitoring_interval" {
  description = "The interval, in seconds, between points when Enhanced Monitoring metrics are collected for the DB instance. To disable collecting Enhanced Monitoring metrics, specify 0. The default is 0. Valid Values: 0, 1, 5, 10, 15, 30, 60."
  type        = number
  default     = 0
}

variable "monitoring_role_arn" {
  description = "The ARN for the IAM role that permits RDS to send enhanced monitoring metrics to CloudWatch Logs. Must be specified if monitoring_interval is non-zero."
  type        = string
  default     = null
}

variable "monitoring_role_name" {
  description = "Name of the IAM role which will be created when create_monitoring_role is enabled."
  type        = string
  default     = "rds-monitoring-role"
}

variable "monitoring_role_use_name_prefix" {
  description = "Determines whether to use `monitoring_role_name` as is or create a unique identifier beginning with `monitoring_role_name` as the specified prefix"
  type        = bool
  default     = false
}

variable "monitoring_role_description" {
  description = "Description of the monitoring IAM role"
  type        = string
  default     = null
}

variable "monitoring_role_permissions_boundary" {
  description = "ARN of the policy that is used to set the permissions boundary for the monitoring IAM role"
  type        = string
  default     = null
}

variable "create_monitoring_role" {
  description = "Create IAM role with a defined name that permits RDS to send enhanced monitoring metrics to CloudWatch Logs."
  type        = bool
  default     = true
}

variable "database_insights_mode" {
  description = "The mode of Database Insights that is enabled for the instance. Valid values: standard, advanced"
  type        = string
  default     = null
}

variable "allow_major_version_upgrade" {
  description = "Indicates that major version upgrades are allowed. Changing this parameter does not result in an outage and the change is asynchronously applied as soon as possible"
  type        = bool
  default     = false
}

variable "auto_minor_version_upgrade" {
  description = "Indicates that minor engine upgrades will be applied automatically to the DB instance during the maintenance window"
  type        = bool
  default     = true
}

variable "apply_immediately" {
  description = "Specifies whether any database modifications are applied immediately, or during the next maintenance window"
  type        = bool
  default     = false
}

variable "maintenance_window" {
  description = "The window to perform maintenance in. Syntax: 'ddd:hh24:mi-ddd:hh24:mi'. Eg: 'Mon:00:00-Mon:03:00'"
  type        = string
  default     = null
}

variable "blue_green_update" {
  description = "Enables low-downtime updates using RDS Blue/Green deployments."
  type = object({
    enabled = optional(bool)
  })
  default = null
}

variable "backup_retention_period" {
  description = "The days to retain backups for"
  type        = number
  default     = null
}

variable "backup_window" {
  description = "The daily time range (in UTC) during which automated backups are created if they are enabled. Example: '09:46-10:16'. Must not overlap with maintenance_window"
  type        = string
  default     = null
}

variable "tags" {
  description = "A mapping of tags to assign to all resources"
  type        = map(string)
  default     = {}
}

variable "db_instance_tags" {
  description = "A map of additional tags for the DB instance"
  type        = map(string)
  default     = {}
}

variable "option_group_name" {
  description = "Name of the DB option group to associate."
  type        = string
  default     = null
}

variable "timezone" {
  description = "Time zone of the DB instance. timezone is currently only supported by Microsoft SQL Server. The timezone can only be set on creation. See MSSQL User Guide for more information."
  type        = string
  default     = null
}

variable "character_set_name" {
  description = "The character set name to use for DB encoding in Oracle instances. This can't be changed. See Oracle Character Sets Supported in Amazon RDS and Collations and Character Sets for Microsoft SQL Server for more information. This can only be set on creation."
  type        = string
  default     = null
}

variable "nchar_character_set_name" {
  description = "The national character set is used in the NCHAR, NVARCHAR2, and NCLOB data types for Oracle instances. This can't be changed."
  type        = string
  default     = null
}

variable "enabled_cloudwatch_logs_exports" {
  description = "List of log types to enable for exporting to CloudWatch logs. If omitted, no logs will be exported. Valid values (depending on engine): alert, audit, error, general, listener, slowquery, trace, postgresql (PostgreSQL), upgrade (PostgreSQL)."
  type        = list(string)
  default     = []
}

variable "timeouts" {
  description = "Updated Terraform resource management timeouts. Applies to `aws_db_instance` in particular to permit resource management times"
  type = object({
    create = optional(string)
    update = optional(string)
    delete = optional(string)
  })
  default = null
}

variable "deletion_protection" {
  description = "The database can't be deleted when this value is set to true."
  type        = bool
  default     = false
}

variable "performance_insights_enabled" {
  description = "Specifies whether Performance Insights are enabled"
  type        = bool
  default     = false
}

variable "performance_insights_retention_period" {
  description = "The amount of time in days to retain Performance Insights data. Either 7 (7 days) or 731 (2 years)."
  type        = number
  default     = 7
}

variable "performance_insights_kms_key_id" {
  description = "The ARN for the KMS key to encrypt Performance Insights data."
  type        = string
  default     = null
}

variable "max_allocated_storage" {
  description = "Specifies the value for Storage Autoscaling"
  type        = number
  default     = 0
}

variable "ca_cert_identifier" {
  description = "Specifies the identifier of the CA certificate for the DB instance"
  type        = string
  default     = null
}

variable "delete_automated_backups" {
  description = "Specifies whether to remove automated backups immediately after the DB instance is deleted"
  type        = bool
  default     = true
}

variable "s3_import" {
  description = "Restore from a Percona Xtrabackup in S3 (only MySQL is supported)"
  type = object({
    source_engine_version = string
    bucket_name           = string
    bucket_prefix         = optional(string)
    ingestion_role        = string
  })
  default = null
}


variable "restore_to_point_in_time" {
  description = "Restore to a point in time (MySQL is NOT supported)"
  type = object({
    restore_time                             = optional(string)
    source_db_instance_automated_backups_arn = optional(string)
    source_db_instance_identifier            = optional(string)
    source_dbi_resource_id                   = optional(string)
    use_latest_restorable_time               = optional(bool)
  })
  default = null
}

variable "network_type" {
  description = "The type of network stack"
  type        = string
  default     = null
}

variable "dedicated_log_volume" {
  description = "Use a dedicated log volume (DLV) for the DB instance. Requires Provisioned IOPS."
  type        = bool
  default     = false
}

variable "upgrade_storage_config" {
  description = "Whether to upgrade the storage file system configuration on the read replica. Can only be set with replicate_source_db."
  type        = bool
  default     = null
}

################################################################################
# CloudWatch Log Group
################################################################################

variable "create_cloudwatch_log_group" {
  description = "Determines whether a CloudWatch log group is created for each `enabled_cloudwatch_logs_exports`"
  type        = bool
  default     = true
}

variable "cloudwatch_log_group_retention_in_days" {
  description = "The number of days to retain CloudWatch logs for the DB instance"
  type        = number
  default     = 7
}

variable "cloudwatch_log_group_kms_key_id" {
  description = "The ARN of the KMS Key to use when encrypting log data"
  type        = string
  default     = null
}

variable "cloudwatch_log_group_skip_destroy" {
  description = "Set to true if you do not wish the log group (and any logs it may contain) to be deleted at destroy time, and instead just remove the log group from the Terraform state"
  type        = bool
  default     = null
}

variable "cloudwatch_log_group_class" {
  description = "Specified the log class of the log group. Possible values are: STANDARD or INFREQUENT_ACCESS"
  type        = string
  default     = null
}

variable "cloudwatch_log_group_tags" {
  description = "Additional tags for the CloudWatch log group(s)"
  type        = map(string)
  default     = {}
}

################################################################################
# Managed Secret Rotation
################################################################################

variable "manage_master_user_password_rotation" {
  description = "Whether to manage the master user password rotation. By default, false on creation, rotation is managed by RDS. There is not currently a way to disable this on initial creation even when set to false. Setting this value to false after previously having been set to true will disable automatic rotation."
  type        = bool
  default     = false
}

variable "master_user_password_rotate_immediately" {
  description = "Specifies whether to rotate the secret immediately or wait until the next scheduled rotation window."
  type        = bool
  default     = null
}

variable "master_user_password_rotation_automatically_after_days" {
  description = "Specifies the number of days between automatic scheduled rotations of the secret. Either automatically_after_days or schedule_expression must be specified."
  type        = number
  default     = null
}

variable "master_user_password_rotation_duration" {
  description = "The length of the rotation window in hours. For example, 3h for a three hour window."
  type        = string
  default     = null
}

variable "master_user_password_rotation_schedule_expression" {
  description = "A cron() or rate() expression that defines the schedule for rotating your secret. Either automatically_after_days or schedule_expression must be specified."
  type        = string
  default     = null
}


terraform {
  required_version = ">= 1.11.1"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.28"
    }

    random = {
      source  = "hashicorp/random"
      version = ">= 3.1"
    }
  }

  provider_meta "aws" {
    user_agent = [
      "github.com/terraform-aws-modules/terraform-aws-rds"
    ]
  }
}