locals {
  name = "tag-policy-test"
}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

data "aws_iam_session_context" "whoami" {
  arn = data.aws_caller_identity.current.arn
}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn-ami-hvm-*-x86_64-gp2"]
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

module "ec2" {
  source  = "terraform-aws-modules/ec2-instance/aws"
  version = "4.3.0"

  name              = local.name
  ami               = data.aws_ami.amazon_linux.id
  instance_type     = "t3.micro"
  availability_zone = element(module.vpc.azs, 0)
  subnet_id         = element(module.vpc.private_subnets, 0)

  root_block_device = [
    {
      encrypted   = true
      volume_type = "gp3"
      volume_size = 8
    },
  ]

  ebs_block_device = [
    {
      device_name = "/dev/sdf"
      volume_type = "gp3"
      volume_size = 5
      encrypted   = true
    }
  ]

  metadata_options {
    http_tokens = "required"
  }

  volume_tags = {
    group       = "sig-k8s-infra"
    environment = "staging"
  }

  tags = {
    group       = "sig-k8s-infra"
    environment = "staging"
  }
}

module "ecr" {
  source  = "terraform-aws-modules/ecr/aws"
  version = "1.6.0"

  repository_name         = local.name
  create_lifecycle_policy = false

  tags = {
    group       = "sig-k8s-infra"
    environment = "staging"
  }
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "19.11.0"

  cluster_name                   = local.name
  cluster_endpoint_public_access = false
  vpc_id                         = module.vpc.vpc_id
  subnet_ids                     = module.vpc.private_subnets
  control_plane_subnet_ids       = module.vpc.intra_subnets

  logging = {
    cluster_logging = [
      {
        types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
        enabled = true
      }
    ]
  }

  eks_managed_node_group_defaults = {
    ami_type                              = "AL2_x86_64"
    instance_types                        = ["t3.large", "t3a.large", "t2.large"]
    attach_cluster_primary_security_group = true
  }

  eks_managed_node_groups = {
    blue = {
      min_size     = 1
      max_size     = 1
      desired_size = 1

      instance_types = ["t3.large"]
    }
    green = {
      min_size     = 1
      max_size     = 1
      desired_size = 1

      instance_types = ["t3.large"]
      capacity_type  = "SPOT"
    }
  }

  tags = {
    group       = "sig-k8s-infra"
    environment = "staging"
  }
}

provider "aws" {
  region = "us-east-2"
}

terraform {
  backend "s3" {
    bucket = "k8s-infra-policy-staging-terraform-state"
    region = "us-east-2"
    key    = "account-1/terraform.state"
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 4.61"
    }
  }
}

variable "tags" {
  type        = map(string)
  description = "Tags for AWS resources"
  default = {
    "managed-by" = "Terraform"
  }
}

terraform {
  required_version = "~> 1.3.0"
}

locals {
  vpc_cidr = "10.0.0.0/16"
  azs      = slice(data.aws_availability_zones.available.names, 0, 3)
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 3.0"

  name = local.name
  cidr = local.vpc_cidr

  azs             = local.azs
  private_subnets = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 4, k)]
  public_subnets  = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 48)]
  intra_subnets   = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 52)]

  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
  }

  tags = {
    group       = "sig-k8s-infra"
    environment = "staging"
  }

  enable_flow_logs = true
  flow_logs_reject = true

  security_group_rules = [
    {
      type              = "egress"
      protocol          = "-1"
      from_port         = 0
      to_port           = 0
      cidr_blocks       = ["0.0.0.0/0"]
      ipv6_cidr_blocks  = ["::/0"]
      description       = "Allow all outbound traffic"
      description_ipv6  = "Allow all outbound IPv6 traffic"
      security_group_id = module.eks.cluster_security_group_id
    }
  ]
}