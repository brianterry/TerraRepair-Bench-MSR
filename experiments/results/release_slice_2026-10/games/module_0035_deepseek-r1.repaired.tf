provider "aws" {
  region = local.region
}

locals {
  name   = var.environment_name
  region = var.aws_region

  vpc_cidr       = var.vpc_cidr
  num_of_subnets = min(length(data.aws_availability_zones.available.names), 3)
  azs            = slice(data.aws_availability_zones.available.names, 0, local.num_of_subnets)

  argocd_secret_manager_name = var.argocd_secret_manager_name_suffix

  hosted_zone_name = var.hosted_zone_name

  tags = {
    Blueprint  = local.name
    GithubRepo = "github.com/aws-ia/terraform-aws-eks-blueprints"
  }
}

data "aws_availability_zones" "available" {
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
  filter {
    name   = "state"
    values = ["available"]
  }
}

module "vpc" {
  source  = "git::https://github.com/terraform-aws-modules/terraform-aws-vpc.git?ref=v5.0.0"

  name = local.name
  cidr = local.vpc_cidr

  azs             = local.azs
  public_subnets  = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 6, k)]
  private_subnets = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 6, k + 10)]

  enable_nat_gateway = true
  single_nat_gateway = true

  enable_flow_log = true
  flow_log_traffic_type = "REJECT"
  create_flow_log_cloudwatch_log_group = true
  create_flow_log_cloudwatch_iam_role = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
  }

  tags = local.tags
}

data "aws_route53_zone" "root" {
  name = local.hosted_zone_name
}

resource "aws_route53_zone" "sub" {
  name = "${local.name}.${local.hosted_zone_name}"
  dnssec_config {
    signing_status = "SIGNING"
  }
}

resource "aws_route53_record" "ns" {
  zone_id = data.aws_route53_zone.root.zone_id
  name    = "${local.name}.${local.hosted_zone_name}"
  type    = "NS"
  ttl     = "30"
  records = aws_route53_zone.sub.name_servers
}

module "acm" {
  source  = "git::https://github.com/terraform-aws-modules/terraform-aws-acm.git?ref=v4.0.0"

  domain_name = "${local.name}.${local.hosted_zone_name}"
  zone_id     = aws_route53_zone.sub.zone_id

  subject_alternative_names = [
    "*.${local.name}.${local.hosted_zone_name}"
  ]

  wait_for_validation = true

  tags = {
    Name = "${local.name}.${local.hosted_zone_name}"
  }
}

resource "random_password" "argocd" {
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "aws_secretsmanager_secret" "argocd" {
  name                    = "${local.argocd_secret_manager_name}.${local.name}"
  recovery_window_in_days = 0
  kms_key_id              = "alias/aws/secretsmanager"
}

resource "aws_secretsmanager_secret_version" "argocd" {
  secret_id     = aws_secretsmanager_secret.argocd.id
  secret_string = random_password.argocd.result
}

resource "aws_secretsmanager_secret_rotation" "argocd" {
  secret_id           = aws_secretsmanager_secret.argocd.id
  rotation_rules {
    automatically_after_days = 30
  }
}

output "vpc_id" {
  description = "The ID of the VPC"
  value       = module.vpc.vpc_id
}

output "aws_route53_zone" {
  description = "The new Route53 Zone"
  value       = aws_route53_zone.sub.name
}

output "aws_acm_certificate_status" {
  description = "Status of Certificate"
  value       = module.acm.acm_certificate_status
}

variable "environment_name" {
  description = "The name of environment Infrastructure stack, feel free to rename it. Used for cluster and VPC names."
  type        = string
  default     = "eks-blueprint"
}

variable "aws_region" {
  description = "AWS Region"
  type        = string
  default     = "us-west-2"
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "argocd_secret_manager_name_suffix" {
  type        = string
  description = "Name of secret manager secret for ArgoCD Admin UI Password"
  default     = "argocd-admin-secret"
}

variable "hosted_zone_name" {
  type        = string
  description = "Route53 domain for the cluster."
  default     = "example.com"
}

terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 4.67"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.0"
    }
  }
}