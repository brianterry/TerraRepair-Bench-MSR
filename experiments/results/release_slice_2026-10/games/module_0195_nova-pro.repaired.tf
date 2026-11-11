provider "aws" {
  region = local.region
}

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  name   = "ex-${basename(path.cwd)}"
  region = "eu-west-1"

  vpc_cidr = "10.0.0.0/16"
  azs      = slice(data.aws_availability_zones.available.names, 0, 3)

  user_data = <<-EOT
    #!/bin/bash
    echo "Hello Terraform!"
  EOT

  tags = {
    Name       = local.name
    Example    = local.name
    Repository = "https://github.com/terraform-aws-modules/terraform-aws-ec2-instance"
  }
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws//modules/vpc"
  version = "3.40.0"

  name = local.name
  cidr = local.vpc_cidr

  azs             = local.azs
  private_subnets = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 4, k)]
  public_subnets  = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 48)]

  enable_flow_logs = true

  tags = local.tags
}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]
  name_regex  = "^al2023-ami-2023.*-x86_64"
}

module "security_group" {
  source  = "terraform-aws-modules/security-group/aws//modules/security-group"
  version = "4.5.0"

  name        = local.name
  description = "Security group for example usage with EC2 instance"
  vpc_id      = module.vpc.vpc_id

  ingress_cidr_blocks = ["0.0.0.0/0"]
  ingress_rules       = ["http-80-tcp", "all-icmp"]

  tags = local.tags
}

resource "aws_placement_group" "web" {
  name     = local.name
  strategy = "cluster"
}

resource "aws_kms_key" "this" {
  enable_key_rotation = true

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        },
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ],
        Resource = "*"
      }
    ]
  })
}

resource "aws_network_interface" "this" {
  subnet_id       = element(module.vpc.private_subnets, 0)
  security_groups = [module.security_group.security_group_id]
}

resource "random_string" "suffix" {
  length  = 2
  numeric = false
  upper   = false
  special = false
}