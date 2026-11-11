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
  # Do not include local zones
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
  private_zone = true
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = local.name
  cidr = local.vpc_cidr

  azs             = local.azs
  public_subnets  = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 6, k)]
  private_subnets = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 6, k + 10)]

  enable_nat_gateway = true
  single_nat_gateway = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
  }

  enable_flow_logs = true
  flow_log_input = {
    traffic_type = "REJECT"
    log_group_arn = "arn:aws:logs:${local.region}:123456789012:log-group:/vpc/flow-logs"
  }

  tags = local.tags
}

# Retrieve existing root hosted zone
data "aws_route53_zone" "root" {
  name = local.hosted_zone_name
}

# Create Sub HostedZone four our deployment
resource "aws_route53_zone" "sub" {
  name = "${local.name}.${local.hosted_zone_name}"
  query_logging_config {
    cloudwatch_log_group_arn = "arn:aws:logs:${local.region}:123456789012:log-group:/route53/query-logs"
  }
  dnssec_config {
    signing_status = "ENABLE"
  }
}

# Validate records for the new HostedZone
resource "aws_route53_record" "ns" {
  zone_id = data.aws_route53_zone.root.zone_id
  name    = "${local.name}.${local.hosted_zone_name}"
  type    = "NS"
  ttl     = "30"
  records = aws_route53_zone.sub.name_servers
}

module "acm" {
  source  = "terraform-aws-modules/acm/aws"
  version = "4.0.0"

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

#---------------------------------------------------------------
# ArgoCD Admin Password credentials with Secrets Manager
# Login to AWS Secrets manager with the same role as Terraform to extract the ArgoCD admin password with the secret name as "argocd"
#---------------------------------------------------------------
resource "random_password" "argocd" {
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "aws_secretsmanager_secret" "argocd" {
  name                    = "${local.argocd_secret_manager_name}.${local.name}"
  recovery_window_in_days = 0 # Set to zero for this example to force delete during Terraform destroy
  kms_key_id              = "arn:aws:kms:${local.region}:123456789012:key/abcd1234-a123-4abc-8def-1234567890ab"
}

resource "aws_secretsmanager_secret_version" "argocd" {
  secret_id     = aws_secretsmanager_secret.argocd.id
  secret_string = random_password.argocd.result
  rotation {
    rotation_lambda_arn = "arn:aws:lambda:${local.region}:123456789012:function:argocd-secret-rotation"
    automatic_rotation  = true
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
      version = "4.67.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "3.0.0"
    }
  }
}