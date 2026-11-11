provider "aws" {
  region = local.region
}

data "aws_availability_zones" "available" {
  state = "available"
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

locals {
  name   = "s3-import"
  region = "eu-west-1"

  vpc_cidr = "10.0.0.0/16"
  azs      = slice(data.aws_availability_zones.available.names, 0, 3)

  tags = {
    Name       = local.name
    Example    = local.name
    Repository = "https://github.com/terraform-aws-modules/terraform-aws-rds"
  }
}

################################################################################
# RDS Module
################################################################################

module "db" {
  source = "../../"

  identifier = local.name

  engine               = "mysql"
  engine_version       = "8.0.43"
  family               = "mysql8.0"
  major_engine_version = "8.0"
  instance_class       = "db.t4g.large"

  allocated_storage     = 20
  max_allocated_storage = 100

  db_name  = "s3Import"
  username = "s3_import_user"
  port     = 3306

  s3_import = {
    source_engine_version = "8.0.43"
    bucket_name           = module.import_s3_bucket.s3_bucket_id
    ingestion_role        = aws_iam_role.s3_import.arn
  }

  multi_az               = true
  db_subnet_group_name   = module.vpc.database_subnet_group
  vpc_security_group_ids = [module.security_group.security_group_id]

  maintenance_window              = "Mon:00:00-Mon:03:00"
  backup_window                   = "03:00-06:00"
  enabled_cloudwatch_logs_exports = ["audit", "general"]

  backup_retention_period = 0
  skip_final_snapshot     = true
  deletion_protection     = false

  tags = local.tags
}

################################################################################
# Supporting Resources
################################################################################

module "vpc" {
  source  = "git::https://github.com/terraform-aws-modules/terraform-aws-vpc.git?ref=v6.0.0"
  version = "~>6.0"

  name = local.name
  cidr = local.vpc_cidr

  azs              = local.azs
  public_subnets   = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k)]
  private_subnets  = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 3)]
  database_subnets = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 6)]

  create_database_subnet_group = true

  enable_flow_log                      = true
  flow_log_destination_type            = "cloud-watch-logs"
  create_flow_log_cloudwatch_log_group = true
  create_flow_log_cloudwatch_iam_role  = true
  flow_log_traffic_type                = "REJECT"

  tags = local.tags
}

module "security_group" {
  source  = "git::https://github.com/terraform-aws-modules/terraform-aws-security-group.git?ref=v5.0.0"
  version = "~>5.0"

  name        = local.name
  description = "S3 import VPC example security group"
  vpc_id      = module.vpc.vpc_id

  ingress_with_self = [
    {
      rule        = "https-443-tcp"
      description = "Allow all internal HTTPs"
    },
  ]

  ingress_with_cidr_blocks = [
    {
      from_port   = 3306
      to_port     = 3306
      protocol    = "tcp"
      description = "MySQL access from within VPC"
      cidr_blocks = module.vpc.vpc_cidr_block
    },
  ]

  computed_egress_with_self = [
    {
      rule        = "https-443-tcp"
      description = "Allow all internal HTTPs"
    },
  ]
  number_of_computed_egress_with_self = 1

  tags = local.tags
}

module "import_s3_bucket" {
  source  = "git::https://github.com/terraform-aws-modules/terraform-aws-s3-bucket.git?ref=v5.0.0"
  version = "~>5.0"

  bucket_prefix = "${local.name}-"
  force_destroy = true

  versioning = {
    enabled = true
  }

  logging = {
    target_bucket = module.import_s3_bucket.s3_bucket_id
    target_prefix = "logs/"
  }

  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = {
        sse_algorithm = "aws:kms"
      }
    }
  }

  tags = local.tags
}

data "aws_iam_policy_document" "s3_import_assume" {
  statement {
    actions = [
      "sts:AssumeRole",
    ]

    principals {
      type        = "Service"
      identifiers = ["rds.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "s3_import" {
  name_prefix           = "${local.name}-"
  description           = "IAM role to allow RDS to import MySQL backup from S3"
  assume_role_policy    = data.aws_iam_policy_document.s3_import_assume.json
  force_detach_policies = true

  tags = local.tags
}

data "aws_iam_policy_document" "s3_import" {
  statement {
    actions = [
      "s3:ListBucket",
      "s3:GetBucketLocation",
    ]

    resources = [
      module.import_s3_bucket.s3_bucket_arn
    ]
  }

  statement {
    actions = [
      "s3:GetObject",
    ]

    resources = [
      "${module.import_s3_bucket.s3_bucket_arn}/*",
    ]
  }
}

resource "aws_iam_role_policy" "s3_import" {
  name_prefix = "${local.name}-"
  role        = aws_iam_role.s3_import.id
  policy      = data.aws_iam_policy_document.s3_import.json

  provisioner "local-exec" {
    command = "unzip backup.zip && aws s3 sync ${path.module}/backup s3://${module.import_s3_bucket.s3_bucket_id}"
  }
}

output "db_instance_address" {
  value = module.db.db_instance_address
}

output "db_instance_arn" {
  value = module.db.db_instance_arn
}

output "db_instance_availability_zone" {
  value = module.db.db_instance_availability_zone
}

output "db_instance_endpoint" {
  value = module.db.db_instance_endpoint
}

output "db_instance_engine" {
  value = module.db.db_instance_engine
}

output "db_instance_engine_version_actual" {
  value = module.db.db_instance_engine_version_actual
}

output "db_instance_hosted_zone_id" {
  value = module.db.db_instance_hosted_zone_id
}

output "db_instance_identifier" {
  value = module.db.db_instance_identifier
}

output "db_instance_resource_id" {
  value = module.db.db_instance_resource_id
}

output "db_instance_status" {
  value = module.db.db_instance_status
}

output "db_instance_name" {
  value = module.db.db_instance_name
}

output "db_instance_username" {
  value = module.db.db_instance_username
  sensitive = true
}

output "db_instance_port" {
  value = module.db.db_instance_port
}

output "db_subnet_group_id" {
  value = module.db.db_subnet_group_id
}

output "db_subnet_group_arn" {
  value = module.db.db_subnet_group_arn
}

output "db_parameter_group_id" {
  value = module.db.db_parameter_group_id
}

output "db_parameter_group_arn" {
  value = module.db.db_parameter_group_arn
}

output "db_instance_cloudwatch_log_groups" {
  value = module.db.db_instance_cloudwatch_log_groups
}

output "db_instance_master_user_secret_arn" {
  value = module.db.db_instance_master_user_secret_arn
}

terraform {
  required_version = ">=1.11.1"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">=6.28"
    }
  }
}