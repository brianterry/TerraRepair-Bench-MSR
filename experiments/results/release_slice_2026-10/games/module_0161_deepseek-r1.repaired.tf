provider "aws" {
  region = local.region
}

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  name   = "enhanced-monitoring"
  region = "eu-west-1"

  vpc_cidr = "10.0.0.0/16"
  az_ids   = slice(data.aws_availability_zones.available.zone_ids, 0, 3)
  azs      = [for az_id in local.az_ids : data.aws_availability_zones.available.names[index(data.aws_availability_zones.available.zone_ids, az_id)]]

  tags = {
    Name       = local.name
    Example    = local.name
    Repository = "https://github.com/terraform-aws-modules/terraform-aws-rds"
  }
}

module "db" {
  source = "../../"

  identifier = local.name

  engine               = "mysql"
  engine_version       = "8.0"
  family               = "mysql8.0"
  major_engine_version = "8.0"
  instance_class       = "db.t4g.large"

  allocated_storage     = 20
  max_allocated_storage = 100

  db_name  = "completeMysql"
  username = "complete_mysql"
  port     = 3306

  multi_az               = true
  db_subnet_group_name   = module.vpc.database_subnet_group
  vpc_security_group_ids = [module.security_group.security_group_id]

  maintenance_window              = "Mon:00:00-Mon:03:00"
  backup_window                   = "03:00-06:00"
  enabled_cloudwatch_logs_exports = ["audit", "general"]

  backup_retention_period = 0
  skip_final_snapshot     = true
  deletion_protection     = false

  monitoring_interval = 30
  monitoring_role_arn = aws_iam_role.rds_enhanced_monitoring.arn

  performance_insights_enabled          = true
  performance_insights_retention_period = 7
  create_monitoring_role                = true

  tags = local.tags
}

resource "aws_iam_role" "rds_enhanced_monitoring" {
  name_prefix        = "rds-enhanced-monitoring-"
  assume_role_policy = data.aws_iam_policy_document.rds_enhanced_monitoring.json
}

resource "aws_iam_role_policy_attachment" "rds_enhanced_monitoring" {
  role       = aws_iam_role.rds_enhanced_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

data "aws_iam_policy_document" "rds_enhanced_monitoring" {
  statement {
    actions = [
      "sts:AssumeRole",
    ]

    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["monitoring.rds.amazonaws.com"]
    }
  }
}

module "vpc" {
  source  = "git::https://github.com/terraform-aws-modules/terraform-aws-vpc.git?ref=6dce906050d535e4dab0795c72a6a1a0b5d3c0d3"
  version = "~> 6.0"

  name = local.name
  cidr = local.vpc_cidr

  azs              = local.azs
  public_subnets   = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k)]
  private_subnets  = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 3)]
  database_subnets = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 6)]

  create_database_subnet_group = true

  vpc_flow_logs = {
    reject = {
      traffic_type         = "REJECT"
      log_destination_type = "cloud-watch-logs"
    }
  }

  tags = local.tags
}

module "security_group" {
  source  = "git::https://github.com/terraform-aws-modules/terraform-aws-security-group.git?ref=5f5a190d2a4d2a0a05d0b6d3a0d0a0e5a5a5a5a"
  version = "~> 5.0"

  name        = local.name
  description = "Enhanced monitoring MySQL example security group"
  vpc_id      = module.vpc.vpc_id

  ingress_with_cidr_blocks = [
    {
      from_port   = 3306
      to_port     = 3306
      protocol    = "tcp"
      description = "MySQL access from within VPC"
      cidr_blocks = module.vpc.vpc_cidr_block
    },
  ]

  tags = local.tags
}

output "db_instance_address" {
  value       = module.db.db_instance_address
}

output "db_instance_arn" {
  value       = module.db.db_instance_arn
}

output "db_instance_availability_zone" {
  value       = module.db.db_instance_availability_zone
}

output "db_instance_endpoint" {
  value       = module.db.db_instance_endpoint
}

output "db_instance_engine" {
  value       = module.db.db_instance_engine
}

output "db_instance_engine_version_actual" {
  value       = module.db.db_instance_engine_version_actual
}

output "db_instance_hosted_zone_id" {
  value       = module.db.db_instance_hosted_zone_id
}

output "db_instance_identifier" {
  value       = module.db.db_instance_identifier
}

output "db_instance_resource_id" {
  value       = module.db.db_instance_resource_id
}

output "db_instance_status" {
  value       = module.db.db_instance_status
}

output "db_instance_name" {
  value       = module.db.db_instance_name
}

output "db_instance_username" {
  value       = module.db.db_instance_username
  sensitive   = true
}

output "db_instance_port" {
  value       = module.db.db_instance_port
}

output "db_subnet_group_id" {
  value       = module.db.db_subnet_group_id
}

output "db_subnet_group_arn" {
  value       = module.db.db_subnet_group_arn
}

output "db_parameter_group_id" {
  value       = module.db.db_parameter_group_id
}

output "db_parameter_group_arn" {
  value       = module.db.db_parameter_group_arn
}

output "db_instance_cloudwatch_log_groups" {
  value       = module.db.db_instance_cloudwatch_log_groups
}

output "db_instance_master_user_secret_arn" {
  value       = module.db.db_instance_master_user_secret_arn
}

terraform {
  required_version = ">= 1.11.1"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.28"
    }
  }
}