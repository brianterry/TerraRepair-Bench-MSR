variable "postgres_name" {
  type        = string
  description = "Name of the application, e.g. `app` or `analytics`"
  default     = "postgres"
}

variable "postgres_admin_user" {
  type        = string
  description = "Postgres admin user name"
  default     = "sentry"
}

variable "postgres_admin_password" {
  type        = string
  description = "Postgres password for the admin user"
  default     = ""
}

variable "postgres_db_name" {
  type        = string
  description = "Postgres database name"
  default     = "sentry"
}

variable "aurora_postgres_engine_version" {
  type        = string
  description = "Database Engine Version for Aurora postgresql"
  default     = "9.6.12"
}

variable "aurora_postgres_cluster_family" {
  type        = string
  description = "Database Engine Version for Aurora postgresql"
  default     = "9.6.12"
}

variable "postgres_instance_type" {
  type        = string
  default     = "db.r4.large"
  description = "EC2 instance type for Postgres cluster"
}

variable "postgres_cluster_size" {
  type        = number
  default     = 2
  description = "Postgres cluster size"
}

variable "postgres_autoscaling_enabled" {
  type        = bool
  default     = false
  description = "Set true to enable the database cluster autoscaler"
}

variable "postgres_autoscaling_min_capacity" {
  type        = number
  default     = 1
  description = "Minimum number of Postgres instances to be maintained by the autoscaler"
}

variable "postgres_autoscaling_max_capacity" {
  type        = number
  default     = 6
  description = "Maximum number of Postgres instances to be maintained by the autoscaler"
}

variable "postgres_cluster_enabled" {
  type        = bool
  default     = true
  description = "Set to false to prevent the module from creating any resources"
}

variable "postgres_iam_database_authentication_enabled" {
  type        = bool
  default     = false
  description = "Specifies whether or mappings of AWS Identity and Access Management (IAM) accounts to database accounts is enabled."
}

resource "random_string" "postgres_admin_password" {
  count   = local.postgres_cluster_enabled ? 1 : 0
  length  = 26
  special = true
}

locals {
  postgres_cluster_enabled = var.postgres_cluster_enabled
  postgres_db_name         = var.postgres_db_name
  postgres_admin_user      = length(var.postgres_admin_user) > 0 ? var.postgres_admin_user : "sentry"
  postgres_admin_password  = length(var.postgres_admin_password) > 0 ? var.postgres_admin_password : join("", random_string.postgres_admin_password.*.result)
}

module "aurora_postgres" {
  source           = "git::https://github.com/cloudposse/terraform-aws-rds-cluster.git?ref=0.16.0"
  namespace        = var.namespace
  stage            = var.stage
  name             = var.postgres_name
  attributes       = ["sentry"]
  engine           = "aurora-postgresql"
  cluster_family   = "aurora-postgresql9.6"
  engine_version   = var.aurora_postgres_engine_version
  instance_type    = var.postgres_instance_type
  cluster_size     = var.postgres_cluster_size
  admin_user       = local.postgres_admin_user
  admin_password   = local.postgres_admin_password
  db_name          = local.postgres_db_name
  db_port          = "5432"
  vpc_id           = module.kops_metadata.vpc_id
  subnets          = module.kops_metadata.private_subnet_ids
  zone_id          = local.zone_id
  cluster_dns_name = "master.postgres-sentry"
  reader_dns_name  = "replicas.postgres-sentry"
  security_groups  = [module.kops_metadata.nodes_security_group_id]
  enabled          = var.postgres_cluster_enabled

  iam_database_authentication_enabled = var.postgres_iam_database_authentication_enabled
  storage_encrypted                   = true
  deletion_protection                 = true
  performance_insights_enabled        = true
}

resource "aws_ssm_parameter" "aurora_postgres_database_name" {
  count       = local.postgres_cluster_enabled ? 1 : 0
  name        = format(local.chamber_parameter_format, local.chamber_service, "sentry_postgres_database")
  value       = module.aurora_postgres.database_name
  description = "Aurora Postgres Database Name for Sentry"
  type        = "SecureString"
  key_id      = local.kms_key_id
  overwrite   = true
}

resource "aws_ssm_parameter" "aurora_postgres_master_username" {
  count       = local.postgres_cluster_enabled ? 1 : 0
  name        = format(local.chamber_parameter_format, local.chamber_service, "sentry_postgres_user")
  value       = module.aurora_postgres.master_username
  description = "Aurora Postgres Username for Sentry's master DB user"
  type        = "SecureString"
  key_id      = local.kms_key_id
  overwrite   = true
}

resource "aws_ssm_parameter" "aurora_postgres_master_password" {
  count       = local.postgres_cluster_enabled ? 1 : 0
  name        = format(local.chamber_parameter_format, local.chamber_service, "sentry_postgres_password")
  value       = local.postgres_admin_password
  description = "Aurora Postgres Password for Sentry's master DB user"
  type        = "SecureString"
  key_id      = local.kms_key_id
  overwrite   = true
}

resource "aws_ssm_parameter" "aurora_postgres_master_hostname" {
  count       = local.postgres_cluster_enabled ? 1 : 0
  name        = format(local.chamber_parameter_format, local.chamber_service, "sentry_postgres_host")
  value       = module.aurora_postgres.master_host
  description = "Aurora Postgres DB Master hostname"
  type        = "SecureString"
  key_id      = local.kms_key_id
  overwrite   = true
}

resource "aws_ssm_parameter" "aurora_postgres_replicas_hostname" {
  count       = local.postgres_cluster_enabled ? 1 : 0
  name        = format(local.chamber_parameter_format, local.chamber_service, "sentry_postgres_replicas_hostname")
  value       = module.aurora_postgres.replicas_host
  description = "Aurora Postgres DB Replicas hostname"
  type        = "SecureString"
  key_id      = local.kms_key_id
  overwrite   = true
}

resource "aws_ssm_parameter" "aurora_postgres_cluster_name" {
  count       = local.postgres_cluster_enabled ? 1 : 0
  name        = format(local.chamber_parameter_format, local.chamber_service, "sentry_postgres_cluster_name")
  value       = module.aurora_postgres.cluster_identifier
  description = "Aurora Postgres DB Cluster Identifier"
  type        = "SecureString"
  key_id      = local.kms_key_id
  overwrite   = true
}

output "aurora_postgres_database_name" {
  value       = module.aurora_postgres.database_name
  description = "Aurora Postgres Database name"
}

output "aurora_postgres_master_username" {
  value       = module.aurora_postgres.master_username
  description = "Aurora Postgres Username for the master DB user"
}

output "aurora_postgres_master_hostname" {
  value       = module.aurora_postgres.master_host
  description = "Aurora Postgres DB Master hostname"
}

output "aurora_postgres_replicas_hostname" {
  value       = module.aurora_postgres.replicas_host
  description = "Aurora Postgres Replicas hostname"
}

output "aurora_postgres_cluster_name" {
  value       = module.aurora_postgres.cluster_identifier
  description = "Aurora Postgres Cluster Identifier"
}


variable "redis_name" {
  type        = string
  default     = "redis"
  description = "Redis name"
}

variable "redis_instance_type" {
  type        = string
  default     = "cache.t2.medium"
  description = "EC2 instance type for Redis cluster"
}

variable "redis_cluster_size" {
  type        = number
  default     = 2
  description = "Redis cluster size"
}

variable "redis_cluster_enabled" {
  type        = bool
  default     = true
  description = "Set to false to prevent the module from creating any resources"
}

variable "redis_params" {
  type = list(object({
    name  = string
    value = string
  }))
  default     = [{ name = "maxmemory-policy", value = "allkeys-lru" }]
  description = "A list of Redis parameters to apply. Note that parameters may differ from a Redis family to another"
}

module "elasticache_redis" {
  source                       = "git::https://github.com/cloudposse/terraform-aws-elasticache-redis.git?ref=0.13.0"
  enabled                      = var.redis_cluster_enabled
  namespace                    = var.namespace
  stage                        = var.stage
  name                         = var.redis_name
  attributes                   = ["sentry"]
  zone_id                      = local.zone_id
  security_groups              = [module.kops_metadata.nodes_security_group_id]
  vpc_id                       = module.kops_metadata.vpc_id
  subnets                      = module.kops_metadata.private_subnet_ids
  maintenance_window           = "sun:03:00-sun:04:00"
  cluster_size                 = var.redis_cluster_size
  instance_type                = var.redis_instance_type
  engine_version               = "4.0.10"
  family                       = "redis4.0"
  port                         = 6379
  alarm_cpu_threshold_percent  = 75
  alarm_memory_threshold_bytes = 10000000
  apply_immediately            = true
  availability_zones           = local.availability_zones
  automatic_failover           = true

  transit_encryption_enabled = false
  auth_token                 = null

  parameter = var.redis_params
}

resource "aws_ssm_parameter" "elasticache_redis_host" {
  count       = local.postgres_cluster_enabled ? 1 : 0
  name        = format(local.chamber_parameter_format, local.chamber_service, "sentry_redis_host")
  value       = module.elasticache_redis.host
  description = "Elasticache host for Sentry"
  type        = "SecureString"
  key_id      = local.kms_key_id
  overwrite   = true
}

output "elasticache_redis_id" {
  value = module.elasticache_redis.id
}

output "elasticache_redis_security_group_id" {
  value = module.elasticache_redis.security_group_id
}

output "elasticache_redis_host" {
  value = module.elasticache_redis.host
}


terraform {
  backend "s3" {}
}

data "aws_availability_zones" "available" {
  state = "available"
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

data "aws_route53_zone" "default" {
  name = var.kops_cluster_name
}

module "kops_metadata" {
  source       = "git::https://github.com/cloudposse/terraform-aws-kops-data-network.git?ref=0.2.0"
  enabled      = true
  cluster_name = var.kops_cluster_name
}

locals {
  null               = ""
  zone_id            = data.aws_route53_zone.default.zone_id
  availability_zones = split(",", length(var.elasticache_availability_zones) == 0 ? join(",", data.aws_availability_zones.available.names) : join(",", var.elasticache_availability_zones))
  chamber_service    = var.chamber_service == "" ? basename(pathexpand(path.module)) : var.chamber_service
  kms_key_id         = length(var.postgres_rds_instance_kms_key_id) > 0 ? var.postgres_rds_instance_kms_key_id : format("alias/%s-%s-chamber", var.namespace, var.stage)

  chamber_parameter_format = "/%s/%s"
}

provider "aws" {
  assume_role {
    role_arn = var.aws_assume_role_arn
  }
}

resource "random_string" "sentry_secret_key" {
  length  = 48
  special = true
}

resource "random_string" "sentry_admin_user_password" {
  length  = 21
  special = false
}

resource "aws_ssm_parameter" "sentry_secret" {
  name        = format(local.chamber_parameter_format, local.chamber_service, "sentry_secret")
  value       = random_string.sentry_secret_key.result
  description = "Secret Key for Sentry to encrypt sessions"
  type        = "SecureString"
  key_id      = local.kms_key_id
  overwrite   = true
}

resource "aws_ssm_parameter" "sentry_admin_user_password" {
  name        = format(local.chamber_parameter_format, local.chamber_service, "sentry_admin_user_password")
  value       = random_string.sentry_admin_user_password.result
  description = "Password for Sentry admin user"
  type        = "SecureString"
  key_id      = local.kms_key_id
  overwrite   = true
}


variable "postgres_rds_instance_name" {
  type        = string
  description = "Name of the application, e.g. `app` or `analytics`"
  default     = "postgres"
}

variable "postgres_rds_instance_user" {
  type        = string
  description = "Postgres admin user name"
}

variable "postgres_rds_instance_password" {
  type        = string
  description = "Postgres password for the admin user"
  default     = ""
}

variable "postgres_rds_instance_db_name" {
  type        = string
  description = "Postgres database name"
}

variable "postgres_rds_instance_type" {
  type        = string
  default     = "db.t3.medium"
  description = "EC2 instance type for Postgres cluster"
}

variable "postgres_rds_instance_enabled" {
  type        = bool
  default     = true
  description = "Set to false to prevent the module from creating any resources"
}

variable "postgres_rds_instance_iam_database_authentication_enabled" {
  type        = bool
  default     = false
  description = "Specifies whether or mappings of AWS Identity and Access Management (IAM) accounts to database accounts is enabled"
}

variable "postgres_rds_instance_cluster_dns_name" {
  type        = string
  description = "Name of the cluster CNAME record to create in the parent DNS zone specified by `zone_name`. If left empty, the name will be auto-asigned using the format `master.var.postgres_rds_instance_name`"
  default     = ""
}

variable "postgres_rds_instance_replicas_dns_name" {
  type        = string
  description = "Name of the reader endpoint CNAME record to create in the parent DNS zone specified by `zone_name`. If left empty, the name will be auto-asigned using the format `replicas.var.postgres_rds_instance_name`"
  default     = ""
}

variable "postgres_rds_instance_allocated_storage" {
  type        = number
  default     = 10
  description = "The allocated storage in GBs"
}

variable "postgres_rds_instance_kms_key_id" {
  type        = string
  default     = ""
  description = "KMS key ID used to encrypt SSM `SecureString` parameters"
}

variable "postgres_rds_instance_hostname" {
  type        = string
  default     = "db"
  description = "The DB host name created in Route53"
}

locals {
  postgres_rds_instance_admin_password = length(var.postgres_rds_instance_password) > 0 ? var.postgres_rds_instance_password : join("", random_string.postgres_rds_instance_password.*.result)
}

resource "random_string" "postgres_rds_instance_password" {
  count            = var.postgres_rds_instance_enabled && length(var.postgres_rds_instance_password) == 0 ? 1 : 0
  length           = 26
  special          = true
  override_special = "!#%^&*()_<>?{}[]~=+"
}

module "rds_instance_postgres" {
  source               = "git::https://github.com/cloudposse/terraform-aws-rds.git?ref=0.19.0"
  enabled              = var.postgres_rds_instance_enabled
  namespace            = var.namespace
  stage                = var.stage
  name                 = var.postgres_rds_instance_name
  engine               = "postgres"
  instance_class       = var.postgres_rds_instance_type
  database_user        = var.postgres_rds_instance_user
  database_password    = local.postgres_rds_instance_admin_password
  database_name        = var.postgres_rds_instance_db_name
  database_port        = "5432"
  dns_zone_id          = local.zone_id
  vpc_id               = module.kops_metadata.vpc_id
  subnet_ids           = module.kops_metadata.private_subnet_ids
  multi_az             = true
  storage_type         = "gp2"
  allocated_storage    = var.postgres_rds_instance_allocated_storage
  storage_encrypted    = "true"
  engine_version       = "9.6"
  major_engine_version = "9.6"
  db_parameter_group   = "postgres9.6"
  publicly_accessible  = false
  host_name            = var.postgres_rds_instance_hostname
}

data "aws_kms_key" "chamber_kms_key" {
  count  = var.postgres_rds_instance_enabled ? 1 : 0
  key_id = local.kms_key_id
}

resource "aws_ssm_parameter" "postgres_rds_instance_master_password" {
  count       = var.postgres_rds_instance_enabled ? 1 : 0
  name        = format(local.chamber_parameter_format, local.chamber_service, "sentry_postgres_password")
  value       = local.postgres_rds_instance_admin_password
  description = "Postgres Password for the Sentry DB user"
  type        = "SecureString"
  key_id      = join("", data.aws_kms_key.chamber_kms_key.*.id)
  overwrite   = true
}


variable "ses_enabled" {
  type        = bool
  default     = false
  description = "Set true to enable SES for sending emails."
}

variable "ses_domain" {
  description = "The domain to create the SES identity for."
  type        = string
}

variable "ses_zone_id" {
  type        = string
  description = "Route53 parent zone ID. If provided (not empty), the module will create Route53 DNS records used for verification"
  default     = ""
}

variable "ses_verify_domain" {
  type        = bool
  description = "If provided the module will create Route53 DNS records used for domain verification."
  default     = null
}

variable "ses_verify_dkim" {
  type        = bool
  description = "If provided the module will create Route53 DNS records used for DKIM verification."
  default     = null
}

module "ses" {
  source        = "git::https://github.com/cloudposse/terraform-aws-ses.git?ref=0.1.0"
  namespace     = var.namespace
  name          = "sentry-ses"
  stage         = var.stage
  enabled       = var.ses_enabled
  domain        = var.ses_domain
  zone_id       = var.ses_zone_id
  verify_dkim   = var.ses_verify_dkim
  verify_domain = var.ses_verify_domain
}
output "smtp_password" {
  sensitive   = true
  value       = module.ses.smtp_password
  description = "The SMTP password. This will be written to the state file in plain text."
}

output "smtp_user" {
  value       = module.ses.smtp_user
  description = "The SMTP user which is access key ID."
}

output "user_name" {
  value       = module.ses.user_name
  description = "Normalized IAM user name."
}

output "user_unique_id" {
  value       = module.ses.user_unique_id
  description = "The unique ID assigned by AWS."
}

output "user_arn" {
  value       = module.ses.user_arn
  description = "The ARN assigned by AWS for this user."
}


variable "aws_assume_role_arn" {
  type = string
}

variable "namespace" {
  type        = string
  description = "Namespace (e.g. `eg` or `cp`)"
}

variable "stage" {
  type        = string
  description = "Stage (e.g. `prod`, `dev`, `staging`)"
}

variable "elasticache_availability_zones" {
  type        = list(string)
  description = "AWS region availability zones for elasticache (e.g.: ['us-west-2a', 'us-west-2b']). If empty will use all available zones"
  default     = []
}

variable "kops_cluster_name" {
  type        = string
  description = "Name of the kops cluster, e.g. us-west-2.prod.cpco.io"
}

variable "chamber_service" {
  type        = string
  default     = "kops"
  description = "`chamber` service name. See [chamber usage](https://github.com/segmentio/chamber#usage) for more details"
}


terraform {
  required_version = "~> 0.12.0"

  required_providers {
    aws    = "~> 2.0"
    random = "~> 2.2"
  }
}