# The resources defined in this file are only used for demonstrating private connectivity
# They are not required for the solution

locals {
  client_name = "${local.name}-client"
}

################################################################################
# VPC
################################################################################

module "client_vpc" {
  source = "git::https://github.com/terraform-aws-modules/terraform-aws-vpc.git?ref=e226cc15eb4e2e1f16117b26916ddb16194bd50f"

  name = local.client_name
  cidr = local.vpc_cidr

  azs             = local.azs
  private_subnets = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 4, k)]
  public_subnets  = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 4, k + 10)]

  enable_nat_gateway = true
  single_nat_gateway = true

  manage_default_network_acl    = true
  default_network_acl_tags      = { Name = "${local.client_name}-default" }
  manage_default_route_table    = true
  default_route_table_tags      = { Name = "${local.client_name}-default" }
  manage_default_security_group = true
  default_security_group_tags   = { Name = "${local.client_name}-default" }

  enable_flow_log                      = true
  create_flow_log_cloudwatch_log_group = true
  create_flow_log_cloudwatch_iam_role  = true
  flow_log_traffic_type                = "REJECT"
  flow_log_destination_type            = "cloud-watch-logs"
  flow_log_max_aggregation_interval    = 60

  tags = merge(local.tags, {
    Name = local.client_name
  })
}

################################################################################
# EC2 Instance
################################################################################

module "client_ec2_instance" {
  source = "git::https://github.com/terraform-aws-modules/terraform-aws-ec2-instance.git?ref=a700a01213a8c30d6ad8d9a5e1c0e132d3eb30f7"

  name = local.client_name

  create_security_group       = false
  create_iam_instance_profile = true
  iam_role_policies = {
    EKSFullAccess                = aws_iam_policy.eks_full_access_policy.arn
    AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }

  vpc_security_group_ids = [module.client_security_group.security_group_id]
  subnet_id              = element(module.client_vpc.private_subnets, 0)

  root_block_device = {
    encrypted = true
  }

  user_data = <<-EOT
    #!/bin/bash

    # Install kubectl
    curl -LO https://dl.k8s.io/release/v${module.eks.cluster_version}.0/bin/linux/amd64/kubectl
    install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

    # Remove default awscli which is v1 - we want latest v2
    yum remove awscli -y
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip -qq awscliv2.zip
    ./aws/install
  EOT

  tags = merge(local.tags, {
    Name = local.client_name
  })
}

resource "aws_iam_policy" "eks_full_access_policy" {
  name        = "EKSFullAccess"
  path        = "/"
  description = "EKS full-access policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "eks:DescribeCluster",
          "eks:ListClusters"
        ]
        Effect   = "Allow"
        Resource = module.eks.cluster_arn
      },
    ]
  })
}

module "client_security_group" {
  source = "git::https://github.com/terraform-aws-modules/terraform-aws-security-group.git?ref=90e83b1e1bf3d0c00a0591d86e3e128f9dfd0f0e"

  name        = local.client_name
  description = "Security group for SSM access to private cluster"
  vpc_id      = module.client_vpc.vpc_id

  egress_with_cidr_blocks = [
    {
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      cidr_blocks = module.client_vpc.vpc_cidr_block
      description = "HTTPS egress to VPC CIDR for PrivateLink and internal services"
    },
  ]

  tags = merge(local.tags, {
    Name = local.client_name
  })
}


################################################################################
# EKS Cluster
################################################################################

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    # This requires the awscli to be installed locally where Terraform is executed
    args = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
  }
}

module "eks" {
  source = "git::https://github.com/terraform-aws-modules/terraform-aws-eks.git?ref=5a00cb8c6d438f2e4cc897ae25573d5e3cdda110"

  cluster_name    = local.name
  cluster_version = "1.30"

  cluster_endpoint_public_access           = false
  enable_cluster_creator_admin_permissions = true

  cluster_enabled_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  access_entries = {
    ec2-access-entry = {
      principal_arn = module.client_ec2_instance.iam_role_arn
      policy_associations = {
        cluster-admin-policy = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = {
            namespaces = []
            type       = "cluster"
          }
        }
      }
    }
  }

  cluster_addons = {
    coredns    = {}
    kube-proxy = {}
    vpc-cni    = {}
  }

  cluster_security_group_additional_rules = {
    # Allow tcp/443 from the NLB IP addresses
    for ip_addr in data.dns_a_record_set.nlb.addrs : "nlb_ingress_${replace(ip_addr, ".", "")}" => {
      description = "Allow ingress from NLB"
      type        = "ingress"
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      cidr_blocks = ["${ip_addr}/32"]
    }
  }

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  node_security_group_enable_recommended_rules = false

  node_security_group_additional_rules = {
    ingress_self_coredns_tcp = {
      description = "Node to node CoreDNS"
      protocol    = "tcp"
      from_port   = 53
      to_port     = 53
      type        = "ingress"
      self        = true
    }
    ingress_self_coredns_udp = {
      description = "Node to node CoreDNS UDP"
      protocol    = "udp"
      from_port   = 53
      to_port     = 53
      type        = "ingress"
      self        = true
    }
    ingress_self_ephemeral = {
      description = "Node to node ingress on ephemeral ports"
      protocol    = "tcp"
      from_port   = 1025
      to_port     = 65535
      type        = "ingress"
      self        = true
    }
    egress_self_all = {
      description = "Node to node all ports/protocols"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      type        = "egress"
      self        = true
    }
    egress_vpc_https = {
      description = "Egress HTTPS to VPC CIDR for API and VPC endpoints"
      protocol    = "tcp"
      from_port   = 443
      to_port     = 443
      type        = "egress"
      cidr_blocks = [local.vpc_cidr]
    }
    egress_vpc_dns_tcp = {
      description = "Egress DNS TCP to VPC CIDR"
      protocol    = "tcp"
      from_port   = 53
      to_port     = 53
      type        = "egress"
      cidr_blocks = [local.vpc_cidr]
    }
    egress_vpc_dns_udp = {
      description = "Egress DNS UDP to VPC CIDR"
      protocol    = "udp"
      from_port   = 53
      to_port     = 53
      type        = "egress"
      cidr_blocks = [local.vpc_cidr]
    }
  }

  eks_managed_node_groups = {
    default = {
      instance_types = ["c5.large"]

      min_size     = 1
      max_size     = 3
      desired_size = 1
    }
  }

  tags = local.tags
}

################################################################################
# VPC
################################################################################

module "vpc" {
  source = "git::https://github.com/terraform-aws-modules/terraform-aws-vpc.git?ref=e226cc15eb4e2e1f16117b26916ddb16194bd50f"

  name = local.name
  cidr = local.vpc_cidr

  azs             = local.azs
  private_subnets = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 4, k)]

  # Disable NAT gateway for fully private networking
  enable_nat_gateway = false

  enable_flow_log                      = true
  create_flow_log_cloudwatch_log_group = true
  create_flow_log_cloudwatch_iam_role  = true
  flow_log_traffic_type                = "REJECT"
  flow_log_destination_type            = "cloud-watch-logs"
  flow_log_max_aggregation_interval    = 60

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
  }

  tags = local.tags
}

# Explicitly create a Internet Gateway here in the Private EKS VPC as without an
# internet gateway, a NLB cannot be created. Config option of create_igw = true
# (default) did not work during the VPC creation as it requires public subnets
# and the related routes that connect them to IGW
resource "aws_internet_gateway" "igw" {
  vpc_id = module.vpc.vpc_id
  tags   = local.tags
}

################################################################################
# VPC Endpoints
################################################################################

module "vpc_endpoints" {
  source = "git::https://github.com/terraform-aws-modules/terraform-aws-vpc.git//modules/vpc-endpoints?ref=e226cc15eb4e2e1f16117b26916ddb16194bd50f"

  vpc_id = module.vpc.vpc_id

  # Security group
  create_security_group      = true
  security_group_name_prefix = "${local.name}-vpc-endpoints-"
  security_group_description = "VPC endpoint security group"
  security_group_rules = {
    ingress_https = {
      description = "HTTPS from VPC"
      cidr_blocks = [module.vpc.vpc_cidr_block]
    }
  }

  endpoints = merge({
    s3 = {
      service         = "s3"
      service_type    = "Gateway"
      route_table_ids = module.vpc.private_route_table_ids
      tags = {
        Name = "${local.name}-s3"
      }
    }
    },
    { for service in toset(["autoscaling", "ecr.api", "ecr.dkr", "ec2", "ec2messages", "elasticloadbalancing", "sts", "kms", "logs", "ssm", "ssmmessages"]) :
      replace(service, ".", "_") =>
      {
        service             = service
        subnet_ids          = module.vpc.private_subnets
        private_dns_enabled = true
        tags                = { Name = "${local.name}-${service}" }
      }
  })

  tags = local.tags
}


provider "aws" {
  region = local.region
}

data "aws_availability_zones" "available" {
  # Do not include local zones
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }

  filter {
    name   = "zone-id"
    values = ["usw2-az1", "usw2-az2", "usw2-az3"]
  }
}

locals {
  name   = basename(path.cwd)
  region = "us-west-2"

  vpc_cidr = "10.0.0.0/16"
  azs      = slice(data.aws_availability_zones.available.names, 0, 3)

  tags = {
    Name       = local.name
    Blueprint  = local.name
    GithubRepo = "github.com/aws-ia/terraform-aws-eks-blueprints"
  }
}


output "ssm_start_session" {
  description = "SSM start session command to connect to remote host created"
  value       = "aws ssm start-session --region ${local.region} --target ${module.client_ec2_instance.id}"
}

output "ssm_test" {
  description = "SSM commands to test connectivity from client EC2 instance to the private EKS cluster"
  value       = <<-EOT

    COMMAND="curl -ks ${module.eks.cluster_endpoint}/readyz"

    COMMAND_ID=$(aws ssm send-command --region ${local.region} \
    --document-name "AWS-RunShellScript" \
    --parameters "commands=[$COMMAND]" \
    --targets "Key=instanceids,Values=${module.client_ec2_instance.id}" \
    --query 'Command.CommandId' \
    --output text)

    aws ssm get-command-invocation --region ${local.region} \
    --command-id $COMMAND_ID \
    --instance-id ${module.client_ec2_instance.id}