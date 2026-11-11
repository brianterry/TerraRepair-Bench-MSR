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
  state = "available"
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.0.1"

  name = local.name
  cidr = local.vpc_cidr

  azs             = local.azs
  public_subnets  = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 6, k)]
  private_subnets = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 6, k + 10)]

  enable_nat_gateway = true
  single_nat_gateway = true
  enable_flow_log     = true
  flow_log_destination_type = "cloud-watch-logs"
  flow_log_destination_arn   = aws_cloudwatch_log_group.vpc_flow_log.arn
  flow_log_traffic_type       = "REJECT"

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
  }

  tags = local.tags
}

resource "aws_cloudwatch_log_group" "vpc_flow_log" {
  name = "${local.name}-vpc-flow-log"
}

# Retrieve existing root hosted zone
data "aws_route53_zone" "root" {
  name = local.hosted_zone_name
}

# Create Sub HostedZone four our deployment
resource "aws_route53_zone" "sub" {
  name = "${local.name}.${local.hosted_zone_name}"
}

resource "aws_route53_query_log" "sub" {
  name          = "${local.name}-query-log"
  cloudwatch_log_group_arn = aws_cloudwatch_log_group.route53_query_log.arn
  zone_id       = aws_route53_zone.sub.id
}

resource "aws_cloudwatch_log_group" "route53_query_log" {
  name = "${local.name}-route53-query-log"
}

resource "aws_route53_zone_dnssec" "sub" {
  zone_id = aws_route53_zone.sub.id
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
  version = "4.0.1"

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

resource "aws_kms_key" "argocd" {
  description             = "KMS key for ArgoCD secret"
  deletion_window_in_days = 10
}

resource "aws_secretsmanager_secret" "argocd" {
  name                    = "${local.argocd_secret_manager_name}.${local.name}"
  recovery_window_in_days = 0 # Set to zero for this example to force delete during Terraform destroy
  kms_key_id              = aws_kms_key.argocd.arn
}

resource "aws_secretsmanager_secret_version" "argocd" {
  secret_id     = aws_secretsmanager_secret.argocd.id
  secret_string = random_password.argocd.result
}

resource "aws_secretsmanager_secret_rotation" "argocd" {
  secret_id           = aws_secretsmanager_secret.argocd.id
  rotation_lambda_arn = aws_lambda_function.argocd_rotation.arn

  rotation_rules {
    automatically_after_days = 30
  }
}

resource "aws_lambda_function" "argocd_rotation" {
  filename      = "lambda_function_payload.zip"
  function_name = "${local.name}-argocd-rotation"
  handler       = "index.handler"
  runtime       = "python3.9"
  role          = aws_iam_role.argocd_rotation.arn
}

resource "aws_iam_role" "argocd_rotation" {
  name        = "${local.name}-argocd-rotation"
  description = "IAM role for ArgoCD secret rotation"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
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