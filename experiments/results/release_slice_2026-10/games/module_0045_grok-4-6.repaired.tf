################################################################################
# Client application (with private access over SSM Systems Manager)
################################################################################

module "client" {
  source = "git::https://github.com/terraform-aws-modules/terraform-aws-ec2-instance.git?ref=ff2b43fb60b7a548f77989c52b20d8e7bed92b2a"

  name = "client"

  instance_type               = "t2.micro"
  subnet_id                   = module.client_vpc.private_subnets[0]
  create_iam_instance_profile = true
  iam_role_description        = "IAM role for client"
  iam_role_policies = {
    AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }
  vpc_security_group_ids = [module.client_sg.security_group_id]

  root_block_device = {
    encrypted = true
  }

  tags = local.tags
}

module "vpc_endpoints" {
  source = "git::https://github.com/terraform-aws-modules/terraform-aws-vpc.git//modules/vpc-endpoints?ref=9e27696ca6d897b6a12d3f73c89d6f6275680465"

  vpc_id = module.client_vpc.vpc_id

  endpoints = { for service in toset(["ssm", "ssmmessages", "ec2messages"]) :
    replace(service, ".", "_") =>
    {
      service             = service
      subnet_ids          = module.client_vpc.private_subnets
      private_dns_enabled = true
      tags                = { Name = "${local.name}-${service}" }
    }
  }

  security_group_ids = [module.endpoint_sg.security_group_id]

  tags = local.tags
}

module "client_sg" {
  source = "git::https://github.com/terraform-aws-modules/terraform-aws-security-group.git?ref=dd02353821f1075fb017537f38060adb0102c072"

  name        = "client"
  description = "Security Group for EC2 Instance Egress"

  vpc_id = module.client_vpc.vpc_id

  egress_with_cidr_blocks = [
    {
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      cidr_blocks = local.client_vpc_cidr
      description = "HTTPS egress to VPC endpoints"
    },
  ]

  egress_with_prefix_list_ids = [
    {
      from_port       = 0
      to_port         = 0
      protocol        = "-1"
      prefix_list_ids = data.aws_ec2_managed_prefix_list.vpc_lattice_ipv4.id
      description     = "Egress to VPC Lattice"
    },
  ]

  tags = local.tags
}

module "endpoint_sg" {
  source = "git::https://github.com/terraform-aws-modules/terraform-aws-security-group.git?ref=dd02353821f1075fb017537f38060adb0102c072"

  name        = "ssm-endpoint"
  description = "Security Group for EC2 Instance Egress"

  vpc_id = module.client_vpc.vpc_id

  ingress_with_cidr_blocks = [for subnet in module.client_vpc.private_subnets_cidr_blocks :
    {
      from_port   = 443
      to_port     = 443
      protocol    = "TCP"
      cidr_blocks = subnet
    }
  ]

  tags = local.tags
}

################################################################################
# Client VPC
################################################################################

module "client_vpc" {
  source = "git::https://github.com/terraform-aws-modules/terraform-aws-vpc.git?ref=9e27696ca6d897b6a12d3f73c89d6f6275680465"

  name = local.name
  cidr = local.client_vpc_cidr

  azs             = local.azs
  private_subnets = [for k, v in local.azs : cidrsubnet(local.client_vpc_cidr, 4, k)]

  enable_flow_log                      = true
  create_flow_log_cloudwatch_log_group = true
  create_flow_log_cloudwatch_iam_role  = true
  flow_log_traffic_type                = "REJECT"

  tags = local.tags
}


################################################################################
# Cluster
################################################################################

module "eks" {
  source = "git::https://github.com/terraform-aws-modules/terraform-aws-eks.git?ref=d126f2c20d53b8f7ef9ec6b3df0a1b6c22694e3a"

  cluster_name                    = local.name
  cluster_version                 = "1.30"
  cluster_endpoint_public_access  = false
  cluster_endpoint_private_access = true
  cluster_endpoint_public_access_cidrs = [local.cluster_vpc_cidr]

  cluster_enabled_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  # Give the Terraform identity admin access to the cluster
  # which will allow resources to be deployed into the cluster
  enable_cluster_creator_admin_permissions = true

  vpc_id     = module.cluster_vpc.vpc_id
  subnet_ids = module.cluster_vpc.private_subnets

  node_security_group_enable_recommended_rules = false
  node_security_group_additional_rules = {
    ingress_cluster_443 = {
      description                   = "Cluster API to node groups"
      protocol                      = "tcp"
      from_port                     = 443
      to_port                       = 443
      type                          = "ingress"
      source_cluster_security_group = true
    }
    ingress_cluster_kubelet = {
      description                   = "Cluster API to node kubelets"
      protocol                      = "tcp"
      from_port                     = 10250
      to_port                       = 10250
      type                          = "ingress"
      source_cluster_security_group = true
    }
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
    ingress_nodes_ephemeral = {
      description = "Node to node ingress on ephemeral ports"
      protocol    = "tcp"
      from_port   = 1025
      to_port     = 65535
      type        = "ingress"
      self        = true
    }
    egress_vpc = {
      description = "Egress to VPC CIDR"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      type        = "egress"
      cidr_blocks = [local.cluster_vpc_cidr]
    }
    egress_lattice = {
      description     = "Egress to VPC Lattice"
      protocol        = "-1"
      from_port       = 0
      to_port         = 0
      type            = "egress"
      prefix_list_ids = [data.aws_ec2_managed_prefix_list.vpc_lattice_ipv4.id]
    }
  }

  eks_managed_node_groups = {
    initial = {
      instance_types = ["m5.large"]

      min_size     = 3
      max_size     = 10
      desired_size = 3
    }
  }

  tags = local.tags
}

################################################################################
# Cluster VPC
################################################################################

module "cluster_vpc" {
  source = "git::https://github.com/terraform-aws-modules/terraform-aws-vpc.git?ref=9e27696ca6d897b6a12d3f73c89d6f6275680465"

  name = local.name
  cidr = local.cluster_vpc_cidr

  azs             = local.azs
  private_subnets = [for k, v in local.azs : cidrsubnet(local.cluster_vpc_cidr, 4, k)]
  public_subnets  = [for k, v in local.azs : cidrsubnet(local.cluster_vpc_cidr, 8, k + 48)]

  enable_nat_gateway = true
  single_nat_gateway = true

  enable_flow_log                      = true
  create_flow_log_cloudwatch_log_group = true
  create_flow_log_cloudwatch_iam_role  = true
  flow_log_traffic_type                = "REJECT"

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
  }

  tags = local.tags
}

################################################################################
# EKS Addons (AWS Gateway API Controller)
################################################################################

module "addons" {
  source = "git::https://github.com/aws-ia/terraform-aws-eks-blueprints-addons.git?ref=a5c06cdca52e0a5b8fa5e9c478679e74a6bdbb4f"

  cluster_name      = module.eks.cluster_name
  cluster_endpoint  = module.eks.cluster_endpoint
  cluster_version   = module.eks.cluster_version
  oidc_provider_arn = module.eks.oidc_provider_arn

  enable_aws_gateway_api_controller = true
  aws_gateway_api_controller = {
    chart_version           = "v1.0.3"
    create_namespace        = true
    namespace               = "aws-application-networking-system"
    source_policy_documents = [data.aws_iam_policy_document.gateway_api_controller.json]
    set = [
      {
        name  = "clusterName"
        value = module.eks.cluster_name
      },
      {
        name  = "log.level"
        value = "debug"
      },
      {
        name  = "clusterVpcId"
        value = module.cluster_vpc.vpc_id
      },
      {
        name  = "defaultServiceNetwork"
        value = ""
      },
      {
        name  = "latticeEndpoint"
        value = "https://vpc-lattice.${local.region}.amazonaws.com"
      }
    ]
    wait = true
  }
  enable_external_dns            = true
  external_dns_route53_zone_arns = try([aws_route53_zone.primary.arn], [])
  external_dns = {
    set = [
      {
        name  = "domainFilters[0]"
        value = "example.com"
      },
      {
        name  = "policy"
        value = "sync"
      },
      {
        name  = "sources[0]"
        value = "crd"
      },
      {
        name  = "sources[1]"
        value = "ingress"
      },
      {
        name  = "txtPrefix"
        value = module.eks.cluster_name
      },
      {
        name  = "extraArgs[0]"
        value = "--crd-source-apiversion=externaldns.k8s.io/v1alpha1"
      },
      {
        name  = "extraArgs[1]"
        value = "--crd-source-kind=DNSEndpoint"
      },
      {
        name  = "crdSourceApiversion"
        value = "externaldns.k8s.io/v1alpha1"
      },
      {
        name  = "crdSourceKind"
        value = "DNSEndpoint"
      }
    ]
  }

  tags = local.tags
}

data "aws_iam_policy_document" "gateway_api_controller" {
  statement {
    sid    = "VpcLatticeAccess"
    effect = "Allow"
    resources = [
      "arn:aws:vpc-lattice:${local.region}:*:service/*",
      "arn:aws:vpc-lattice:${local.region}:*:service-network/*",
      "arn:aws:vpc-lattice:${local.region}:*:targetgroup/*",
      "arn:aws:vpc-lattice:${local.region}:*:listener/*",
      "arn:aws:vpc-lattice:${local.region}:*:rule/*",
      "arn:aws:vpc-lattice:${local.region}:*:authpolicy/*",
      "arn:aws:vpc-lattice:${local.region}:*:service-network-service-association/*",
      "arn:aws:vpc-lattice:${local.region}:*:service-network-vpc-association/*",
      "arn:aws:vpc-lattice:${local.region}:*:accesslogsubscription/*",
    ]

    actions = [
      "vpc-lattice:*",
    ]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [local.region]
    }
  }

  statement {
    sid    = "CreateServiceLinkedRole"
    effect = "Allow"
    resources = [
      "arn:aws:iam::*:role/aws-service-role/vpc-lattice.amazonaws.com/AWSServiceRoleForVpcLattice"
    ]

    actions = [
      "iam:CreateServiceLinkedRole",
    ]

    condition {
      test     = "StringEquals"
      variable = "iam:AWSServiceName"
      values   = ["vpc-lattice.amazonaws.com"]
    }
  }

  statement {
    sid       = "DescribeEC2Resources"
    effect    = "Allow"
    resources = ["*"]

    actions = [
      "ec2:DescribeVpcs",
      "ec2:DescribeSubnets",
      "ec2:DescribeTags",
      "ec2:DescribeSecurityGroups",
      "tag:GetResources",
    ]
  }

  statement {
    sid    = "LogDelivery"
    effect = "Allow"
    resources = [
      "arn:aws:logs:${local.region}:*:log-group:*",
      "arn:aws:logs:${local.region}:*:destination:*",
    ]

    actions = [
      "logs:CreateLogDelivery",
      "logs:GetLogDelivery",
      "logs:UpdateLogDelivery",
      "logs:DeleteLogDelivery",
      "logs:ListLogDeliveries",
    ]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [local.region]
    }
  }
}

################################################################################
# Demo applications
################################################################################

resource "helm_release" "demo_application" {
  name             = "demo-application"
  chart            = "./charts/demo-application"
  create_namespace = true
  namespace        = "apps"

  depends_on = [module.addons]
}

################################################################################
# Update cluster security group to allow access from VPC Lattice
################################################################################

data "aws_ec2_managed_prefix_list" "vpc_lattice_ipv4" {
  name = "com.amazonaws.${local.region}.vpc-lattice"
}

resource "aws_vpc_security_group_ingress_rule" "cluster_sg_ingress" {
  security_group_id = module.eks.node_security_group_id

  description    = "Allow inbound traffic from VPC Lattice"
  prefix_list_id = data.aws_ec2_managed_prefix_list.vpc_lattice_ipv4.id
  ip_protocol    = "-1"
}


################################################################################
# VPC Lattice service network
################################################################################

resource "aws_vpclattice_service_network" "this" {
  name      = "my-services"
  auth_type = "NONE"

  tags = local.tags
}

resource "aws_vpclattice_service_network_vpc_association" "cluster_vpc" {
  vpc_identifier             = module.cluster_vpc.vpc_id
  service_network_identifier = aws_vpclattice_service_network.this.id
}

resource "aws_vpclattice_service_network_vpc_association" "client_vpc" {
  vpc_identifier             = module.client_vpc.vpc_id
  service_network_identifier = aws_vpclattice_service_network.this.id
}

resource "time_sleep" "wait_for_lattice_resources" {
  depends_on = [helm_release.demo_application]

  create_duration = "120s"
}

################################################################################
# Custom domain name for VPC lattice service
# Records will be created by external-dns using DNSEndpoint objects which
# are created by the VPC Lattice gateway api controller when creating HTTPRoutes
################################################################################

resource "aws_route53_zone" "primary" {
  name = "example.com"

  vpc {
    vpc_id = module.client_vpc.vpc_id
  }

  tags = local.tags
}


provider "aws" {
  region = local.region
}

data "aws_availability_zones" "available" {
  #Do not include local zones
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
  filter {
    name   = "zone-id"
    values = ["usw2-az1", "usw2-az2", "usw2-az3"]
  }
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      # This requires the awscli to be installed locally where Terraform is executed
      args = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
    }
  }
}

locals {
  name   = basename(path.cwd)
  region = "us-west-2"

  cluster_vpc_cidr = "10.0.0.0/16"
  client_vpc_cidr  = "10.1.0.0/16"
  azs              = slice(data.aws_availability_zones.available.names, 0, 3)

  tags = {
    Blueprint  = local.name
    GithubRepo = "github.com/aws-ia/terraform-aws-eks-blueprints"
  }
}


output "configure_kubectl" {
  description = "Configure kubectl: make sure you're logged in with the correct AWS profile and run the following command to update your kubeconfig"
  value       = "aws eks update-kubeconfig --name ${module.eks.cluster_name} --alias ${module.eks.cluster_name} --region ${local.region}"
}




terraform {
  required_version = ">= 1.3"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.34, < 6.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.9, < 3.0"
    }
    time = {
      source  = "hashicorp/time"
      version = ">= 0.10"
    }
  }
}