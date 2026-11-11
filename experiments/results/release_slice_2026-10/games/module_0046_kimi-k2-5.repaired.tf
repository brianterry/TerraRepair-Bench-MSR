################################################################################
# Cluster
################################################################################

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.8"

  cluster_name                   = local.name
  cluster_version                = "1.30"
  cluster_endpoint_public_access = false

  cluster_enabled_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  # Give the Terraform identity admin access to the cluster
  # which will allow resources to be deployed into the cluster
  enable_cluster_creator_admin_permissions = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  eks_managed_node_groups = {
    initial = {
      instance_types = ["m5.large"]

      min_size     = 3
      max_size     = 10
      desired_size = 3
    }
  }

  cluster_security_group_additional_rules = {
    vpc_lattice_ingress = {
      description = "Allow VPC Lattice traffic"
      type        = "ingress"
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      prefix_list_ids = [data.aws_ec2_managed_prefix_list.vpc_lattice_ipv4.id]
    }
  }

  tags = local.tags
}



################################################################################
# EKS Blueprints Addons
################################################################################

module "eks_blueprints_addons" {
  source  = "aws-ia/eks-blueprints-addons/aws"
  version = "~> 1.1"

  cluster_name      = module.eks.cluster_name
  cluster_endpoint  = module.eks.cluster_endpoint
  cluster_version   = module.eks.cluster_version
  oidc_provider_arn = module.eks.oidc_provider_arn

  # EKS Addons
  eks_addons = {
    coredns    = {}
    kube-proxy = {}
    vpc-cni = {
      preserve    = true
      most_recent = true

      timeouts = {
        create = "25m"
        delete = "10m"
      }

    }
    eks-pod-identity-agent = {}
  }

  enable_aws_gateway_api_controller = true
  aws_gateway_api_controller = {
    chart_version           = "v1.0.5"
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
        value = module.vpc.vpc_id
      },
      {
        name  = "defaultServiceNetwork"
        value = "lattice-gateway" # Specify this parameter to create a default VPC lattice service
      }
    ]
    wait = true
  }
  enable_external_dns            = true
  external_dns_route53_zone_arns = try([data.terraform_remote_state.environment.outputs.route53_private_zone_arn], [])
  external_dns = {
    create_role = true,
    set = [
      {
        name  = "domainFilters[0]"
        value = local.domain
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

module "eks_blueprints_addon_kyverno" {
  source  = "aws-ia/eks-blueprints-addon/aws"
  version = "~> 1.1" #ensure to update this to the latest/desired version

  chart            = "kyverno"
  chart_version    = "3.0.5"
  repository       = "https://kyverno.github.io/kyverno"
  description      = "Kyverno"
  namespace        = "kyverno"
  create_namespace = true
}

data "aws_iam_policy_document" "gateway_api_controller" {
  statement {
    sid       = "VPCLatticeAccess"
    effect    = "Allow"
    resources = ["arn:aws:vpc-lattice:${local.region}:${data.aws_caller_identity.current.account_id}:service/*"]

    actions = [
      "vpc-lattice:CreateService",
      "vpc-lattice:UpdateService",
      "vpc-lattice:DeleteService",
      "vpc-lattice:CreateTargetGroup",
      "vpc-lattice:UpdateTargetGroup",
      "vpc-lattice:DeleteTargetGroup",
      "vpc-lattice:RegisterTargets",
      "vpc-lattice:DeregisterTargets",
      "vpc-lattice:CreateListener",
      "vpc-lattice:UpdateListener",
      "vpc-lattice:DeleteListener",
      "vpc-lattice:CreateRule",
      "vpc-lattice:UpdateRule",
      "vpc-lattice:DeleteRule",
      "vpc-lattice:CreateServiceNetwork",
      "vpc-lattice:UpdateServiceNetwork",
      "vpc-lattice:DeleteServiceNetwork",
      "vpc-lattice:AssociateServiceNetworkVpc",
      "vpc-lattice:DisassociateServiceNetworkVpc",
      "vpc-lattice:AssociateServiceNetworkService",
      "vpc-lattice:DisassociateServiceNetworkService",
      "vpc-lattice:PutResourcePolicy",
      "vpc-lattice:DeleteResourcePolicy",
      "vpc-lattice:GetService",
      "vpc-lattice:GetTargetGroup",
      "vpc-lattice:GetListener",
      "vpc-lattice:GetRule",
      "vpc-lattice:GetServiceNetwork",
      "vpc-lattice:ListServices",
      "vpc-lattice:ListTargetGroups",
      "vpc-lattice:ListListeners",
      "vpc-lattice:ListRules",
      "vpc-lattice:ListServiceNetworks",
      "vpc-lattice:ListServiceNetworkVpcAssociations",
      "vpc-lattice:ListServiceNetworkServiceAssociations",
      "vpc-lattice:ListTargets",
      "vpc-lattice:ListTagsForResource",
      "vpc-lattice:TagResource",
      "vpc-lattice:UntagResource",
    ]
  }

  statement {
    sid       = "IAMCreateServiceLinkedRole"
    effect    = "Allow"
    resources = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/aws-service-role/vpc-lattice.amazonaws.com/AWSServiceRoleForVpcLattice"]
    actions   = ["iam:CreateServiceLinkedRole"]
    condition {
      test     = "StringEquals"
      variable = "iam:AWSServiceName"
      values   = ["vpc-lattice.amazonaws.com"]
    }
  }

  statement {
    sid       = "EC2Describe"
    effect    = "Allow"
    resources = ["*"]
    actions = [
      "ec2:DescribeVpcs",
      "ec2:DescribeSubnets",
      "ec2:DescribeTags",
      "ec2:DescribeSecurityGroups",
    ]
  }

  statement {
    sid       = "LogsDelivery"
    effect    = "Allow"
    resources = ["arn:aws:logs:${local.region}:${data.aws_caller_identity.current.account_id}:*"]
    actions = [
      "logs:CreateLogDelivery",
      "logs:GetLogDelivery",
      "logs:UpdateLogDelivery",
      "logs:DeleteLogDelivery",
      "logs:ListLogDeliveries",
    ]
  }

  statement {
    sid       = "Tagging"
    effect    = "Allow"
    resources = ["*"]
    actions   = ["tag:GetResources"]
  }
}

################################################################################
# Platform applications
################################################################################

resource "helm_release" "platform_application" {
  name             = "platform-${terraform.workspace}"
  chart            = "./charts/platform"
  create_namespace = true
  namespace        = "lattice-gateway"
  force_update     = true

  #replace = true # This will force a re-deployment

  values = [
    <<EOF
    awsAccountID: "${data.aws_caller_identity.current.account_id}"
    version : "v1"

    allowedCluster: ${terraform.workspace == "cluster1" ? "eks-cluster2" : "eks-cluster1"}
    allowedNamespace: "apps"

    certificateArn: ${local.certificate_arn}

    acmpCAArn: ${local.acmpca_arn}

    customDomain: ${local.custom_domain}
  EOF
  ]

  depends_on = [module.eks_blueprints_addons, aws_eks_pod_identity_association.apps]
}

################################################################################
# Demo applications
################################################################################

resource "helm_release" "demo_application" {
  name             = "demo-${terraform.workspace}"
  chart            = "./charts/demo"
  create_namespace = true
  namespace        = local.app_namespace
  force_update     = true

  #replace = true # This will force a re-deployment

  values = [
    <<EOF
    awsAccountID: "${data.aws_caller_identity.current.account_id}"
    version : "v1"

    allowedCluster: ${terraform.workspace == "cluster1" ? "eks-cluster2" : "eks-cluster1"}
    allowedNamespace: "apps"

    certificateArn: ${local.certificate_arn}

    customDomain: ${local.custom_domain}
  EOF
  ]

  depends_on = [module.eks_blueprints_addons, aws_eks_pod_identity_association.apps, helm_release.platform_application]
}

################################################################################
# Update cluster security group to allow access from VPC Lattice
################################################################################

data "aws_ec2_managed_prefix_list" "vpc_lattice_ipv4" {
  name = "com.amazonaws.${local.region}.vpc-lattice"
}

resource "aws_vpc_security_group_ingress_rule" "cluster_sg_ingress" {
  description       = "Allow VPC Lattice traffic to cluster"
  security_group_id = module.eks.node_security_group_id

  prefix_list_id = data.aws_ec2_managed_prefix_list.vpc_lattice_ipv4.id
  ip_protocol    = "-1"
}


################################################################################
# Associate EKS pod identity for out application
################################################################################

resource "aws_eks_pod_identity_association" "apps" {
  cluster_name    = module.eks.cluster_name
  namespace       = local.app_namespace
  service_account = "default"
  role_arn        = data.terraform_remote_state.environment.outputs.vpc_lattice_client_role_arn
}


provider "aws" {
  region = local.region
}

data "aws_caller_identity" "current" {}

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
  name   = "eks-${terraform.workspace}"
  region = "us-west-2"

  cluster_vpc_cidr = "10.0.0.0/16"
  azs              = slice(data.aws_availability_zones.available.names, 0, 3)

  domain          = data.terraform_remote_state.environment.outputs.custom_domain_name
  certificate_arn = data.terraform_remote_state.environment.outputs.aws_acm_cert_arn
  acmpca_arn      = data.terraform_remote_state.environment.outputs.aws_acmpca_cert_authority_arn
  custom_domain   = data.terraform_remote_state.environment.outputs.custom_domain_name

  app_namespace = "apps"

  tags = {
    Blueprint  = local.name
    GithubRepo = "github.com/aws-ia/terraform-aws-eks-blueprints"
  }
}


output "configure_kubectl" {
  description = "Configure kubectl: make sure you're logged in with the correct AWS profile and run the following command to update your kubeconfig"
  value       = "aws eks update-kubeconfig --name ${module.eks.cluster_name} --alias ${module.eks.cluster_name} --region ${local.region}"
}


# Define terraform state for environment stack

data "terraform_remote_state" "environment" {
  backend = "local"

  config = {
    path = "${path.module}/../environment/terraform.tfstate"
  }
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
  }
}


################################################################################
# Cluster VPC
################################################################################

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

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
  flow_log_max_aggregation_interval    = 60
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
# Associate private_hosted_zone with VPC
################################################################################

resource "aws_route53_zone_association" "private_zone_association" {
  zone_id = data.terraform_remote_state.environment.outputs.private_zone_id
  vpc_id  = module.vpc.vpc_id
}