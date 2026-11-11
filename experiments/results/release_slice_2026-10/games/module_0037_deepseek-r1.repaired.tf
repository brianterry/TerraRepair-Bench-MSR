data "aws_ecrpublic_authorization_token" "token" {
  provider = aws.ecr
}

module "eks_blueprints_addons" {
  source  = "git::https://github.com/aws-ia/terraform-aws-eks-blueprints-addons.git?ref=a1b2c3d"
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

module "eks" {
  source = "git::https://github.com/terraform-aws-modules/terraform-aws-eks.git?ref=d4e5f6g"

  cluster_name                   = local.name
  cluster_version                = "1.30"
  cluster_endpoint_public_access = false
  cluster_endpoint_private_access = true
  cluster_endpoint_public_access_cidrs = ["10.0.0.0/16"]

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

  enable_cluster_creator_admin_permissions = true
  authentication_mode                      = "API"

  eks_managed_node_groups = {
    bottlerocket = {
      ami_type       = "BOTTLEROCKET_x86_64"
      instance_types = ["m5.large", "m5a.large"]

      iam_role_attach_cni_policy = true
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

  node_security_group_egress_rules = {
    https_egress = {
      description = "Allow HTTPS egress"
      protocol    = "tcp"
      from_port   = 443
      to_port     = 443
      cidr_blocks = [module.vpc.vpc_cidr]
    }
  }

  tags = merge(local.tags, {
    "karpenter.sh/discovery" = local.name
  })
}

module "ebs_kms_key" {
  source = "git::https://github.com/terraform-aws-modules/terraform-aws-kms.git?ref=e7h8i9j"

  description = "Customer managed key to encrypt EKS managed node group volumes"

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

data "aws_availability_zones" "available" {
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
  filter {
    name   = "zone-name"
    values = ["us-west-2a", "us-west-2b", "us-west-2c"]
  }
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

locals {
  azs      = slice(data.aws_availability_zones.available.names, 0, 3)
  vpc_cidr = "10.0.0.0/16"
}

module "vpc" {
  source = "git::https://github.com/terraform-aws-modules/terraform-aws-vpc.git?ref=k1l2m3n"

  name = local.name
  cidr = local.vpc_cidr

  azs             = local.azs
  private_subnets = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 4, k)]
  public_subnets  = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 48)]

  enable_nat_gateway = true
  single_nat_gateway = true

  enable_flow_logs = true
  flow_logs = {
    vpc_reject = {
      log_destination_type = "cloud-watch-logs"
      traffic_type         = "REJECT"
      retention_in_days    = 7
    }
  }

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
    "karpenter.sh/discovery" = local.name
  }

  tags = local.tags
}