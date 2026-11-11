################################################################################
# EKS Blueprints Addons
################################################################################
data "aws_ecrpublic_authorization_token" "token" {
  provider = aws.ecr
}

module "eks_blueprints_addons" {
  source  = "github.com/aws-ia/terraform-aws-eks-blueprints-addons@<COMMIT_HASH>"
  version = "~> 1.16"

  cluster_name      = module.eks.cluster_name
  cluster_endpoint  = module.eks.cluster_endpoint
  cluster_version   = module.eks.cluster_version
  oidc_provider_arn = module.eks.oidc_provider_arn

  enable_cert_manager = true
  cert_manager = {
    wait          = true
    wait_for_jobs = true
    values = [<<-EOT
      tolerations:
      - key: "CriticalAddonsOnly"
        operator: "Exists"
      cainjector:
        tolerations:
        - key: "CriticalAddonsOnly"
          operator: "Exists"
      webhook:
        tolerations:
        - key: "CriticalAddonsOnly"
          operator: "Exists"
      startupapicheck:
        tolerations:
        - key: "CriticalAddonsOnly"
          operator: "Exists"
    EOT
    ]
  }

  enable_karpenter = true
  karpenter = {
    repository_username = data.aws_ecrpublic_authorization_token.token.user_name
    repository_password = data.aws_ecrpublic_authorization_token.token.password
  }

  enable_bottlerocket_update_operator = true
  bottlerocket_update_operator = {
    values = [<<-EOT
      scheduler_cron_expression: "* * * * * * *"
      placement:
        agent:
          tolerations:
            - key: "CriticalAddonsOnly"
              operator: "Exists"
        controller:
          tolerations:
            - key: "CriticalAddonsOnly"
              operator: "Exists"
        apiserver:
          tolerations:
            - key: "CriticalAddonsOnly"
              operator: "Exists"
    EOT
    ]
  }

  tags = local.tags
}

################################################################################
# Karpenter resources
################################################################################
resource "aws_eks_access_entry" "karpenter" {

  cluster_name  = module.eks.cluster_name
  principal_arn = module.eks_blueprints_addons.karpenter.node_iam_role_arn
  type          = "EC2_LINUX"

  tags = local.tags

  depends_on = [module.eks_blueprints_addons]
}

resource "helm_release" "karpenter_resources" {
  name  = "karpenter-resources"
  chart = "./karpenter-resources"
  set_list {
    name  = "nodepool.zone"
    value = local.azs
  }
  values = [<<-EOT
    ec2nodeclass:
      securityGroupSelectorTerms:
        tags: ${module.eks.cluster_name}
      subnetSelectorTerms:
        tags: ${module.eks.cluster_name}
      tags: ${module.eks.cluster_name}
      role: ${split("/", module.eks_blueprints_addons.karpenter.node_iam_role_arn)[1]}
      blockDeviceMappings:
        ebs:
          kmsKeyID: ${module.ebs_kms_key.key_id}
  EOT
  ]

  depends_on = [module.eks_blueprints_addons]
}


################################################################################
# EKS Cluster
################################################################################
module "eks" {
  source  = "github.com/terraform-aws-modules/eks/aws@<COMMIT_HASH>"
  version = "~> 20.20"

  cluster_name                   = local.name
  cluster_version                = "1.30"
  cluster_endpoint_public_access  = false

  cluster_enabled_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  cluster_addons = {
    coredns = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent    = true
      before_compute = true
    }
  }
  # Give the Terraform identity admin access to the cluster
  # which will allow resources to be deployed into the cluster
  enable_cluster_creator_admin_permissions = true
  authentication_mode                      = "API"

  eks_managed_node_groups = {
    bottlerocket = {
      ami_type       = "BOTTLEROCKET_x86_64"
      instance_types = ["m5.large", "m5a.large"]

      iam_role_attach_cni_policy = true
      # The below AMI release version is for testing purposes in order to validate Botterocket Update Operator.
      ami_release_version = "1.20.0-fcf71a47"

      min_size     = 1
      max_size     = 5
      desired_size = 3

      ebs_optimized     = true
      enable_monitoring = true
      block_device_mappings = {
        xvda = {
          device_name = "/dev/xvda"
          ebs = {
            encrypted             = true
            kms_key_id            = module.ebs_kms_key.key_arn
            delete_on_termination = true
          }
        }
        xvdb = {
          device_name = "/dev/xvdb"
          ebs = {
            encrypted             = true
            kms_key_id            = module.ebs_kms_key.key_arn
            delete_on_termination = true
          }
        }
      }

      # The following block customize your Bottlerocket instances, including kubernetes tags, host and kernel parameters, and user-data.
      bootstrap_extra_args = <<-EOT
            [settings.host-containers.admin]
            enabled = false

            [settings.host-containers.control]
            enabled = true

            [settings.kernel]
            lockdown = "integrity"

            [settings.kubernetes.node-labels]
            "bottlerocket.aws/updater-interface-version" = "2.0.0"

            [settings.kubernetes.node-taints]
            "CriticalAddonsOnly" = "true:NoSchedule"
          EOT
    }
  }

  tags = merge(local.tags, {
    "karpenter.sh/discovery" = local.name
  })
}

module "ebs_kms_key" {
  source  = "github.com/terraform-aws-modules/kms/aws@<COMMIT_HASH>"
  version = "~> 1.5"

  description = "Customer managed key to encrypt EKS managed node group volumes"

  # Policy
  key_administrators = [
    data.aws_caller_identity.current.arn
  ]

  key_service_roles_for_autoscaling = [
    "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/aws-service-role/autoscaling.amazonaws.com/AWSServiceRoleForAutoScaling",
    module.eks.cluster_iam_role_arn,
    module.eks_blueprints_addons.karpenter.iam_role_arn
  ]

  aliases = ["eks/${local.name}/ebs"]

  tags = local.tags
}


################################################################################
# Providers
################################################################################
data "aws_availability_zones" "available" {
  # Do not include local zones
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
  state  = "available"
}

data "aws_caller_identity" "current" {}

locals {
  name   = substr(basename(path.cwd), 0, 12)
  region = "us-west-2"
  tags = {
    Sample     = local.name
    GithubRepo = "github.com/aws-ia/terraform-aws-eks-blueprints"
  }
}

provider "aws" {
  region = local.region
}

# This provider is required for ECR to authenticate with public repos. Please note ECR authentication requires us-east-1 as region hence its hardcoded below.
# If your region is same as us-east-1 then you can just use one aws provider
provider "aws" {
  alias  = "ecr"
  region = "us-east-1"
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", local.region]
  }
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", local.region]
    }
  }
}


################################################################################
# Outputs
################################################################################
output "configure_kubectl" {
  description = "Configure kubectl: make sure you're logged in with the correct AWS profile and run the following command to update your kubeconfig."
  value       = "aws eks --region ${local.region} update-kubeconfig --name ${module.eks.cluster_name}"
}


terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.34, < 6.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.9, < 3.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.20"
    }
  }
}


################################################################################
# VPC
################################################################################
locals {
  azs      = slice(data.aws_availability_zones.available.names, 0, 3)
  vpc_cidr = "10.0.0.0/16"
}

module "vpc" {
  source  = "github.com/terraform-aws-modules/vpc/aws@<COMMIT_HASH>"
  version = "~> 5.9"

  name = local.name
  cidr = local.vpc_cidr

  azs             = local.azs
  private_subnets = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 4, k)]
  public_subnets  = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 48)]

  enable_nat_gateway = true
  single_nat_gateway = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
    # Tags subnets for Karpenter auto-discovery
    "karpenter.sh/discovery" = local.name
  }

  tags = local.tags
  flow_logs_reject = true
}