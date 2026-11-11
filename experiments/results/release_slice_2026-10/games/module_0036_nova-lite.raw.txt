```hcl
# Required for public ECR where Karpenter artifacts are hosted
provider "aws" {
  region = "us-east-1"
  alias  = "ecr"
}

locals {
  environment = var.environment_name
  service     = var.service_name
  region      = var.aws_region

  env  = local.service
  name = "${local.environment}-${local.service}"

  # Mapping
  hosted_zone_name                            = var.hosted_zone_name
  ingress_type                                = var.ingress_type
  aws_secret_manager_git_private_ssh_key_name = var.aws_secret_manager_git_private_ssh_key_name
  cluster_version                             = var.cluster_version
  argocd_secret_manager_name_suffix           = var.argocd_secret_manager_name_suffix
  eks_admin_role_name                         = var.eks_admin_role_name

  gitops_workloads_url      = "${var.gitops_workloads_org}/${var.gitops_workloads_repo}"
  gitops_workloads_path     = var.gitops_workloads_path
  gitops_workloads_revision = var.gitops_workloads_revision

  gitops_addons_url      = "${var.gitops_addons_org}/${var.gitops_addons_repo}"
  gitops_addons_basepath = var.gitops_addons_basepath
  gitops_addons_path     = var.gitops_addons_path
  gitops_addons_revision = var.gitops_addons_revision

  # Route 53 Ingress Weights
  argocd_route53_weight      = var.argocd_route53_weight
  route53_weight             = var.route53_weight
  ecsfrontend_route53_weight = var.ecsfrontend_route53_weight

  eks_cluster_domain = "${local.environment}.${local.hosted_zone_name}" # for external-dns

  tag_val_vpc            = local.environment
  tag_val_public_subnet  = "${local.environment}-public-"
  tag_val_private_subnet = "${local.environment}-private-"

  node_group_name = "managed-ondemand"

  #---------------------------------------------------------------
  # ARGOCD ADD-ON APPLICATION
  #---------------------------------------------------------------

  aws_addons = {
    enable_cert_manager          = true
    enable_aws_ebs_csi_resources = true # generate gp2 and gp3 storage classes for ebs-csi
    #enable_aws_efs_csi_driver                    = true
    #enable_aws_fsx_csi_driver                    = true
    enable_aws_cloudwatch_metrics = true
    #enable_aws_privateca_issuer                  = true
    #enable_cluster_autoscaler                    = true
    enable_external_dns                 = true
    enable_external_secrets             = true
    enable_aws_load_balancer_controller = true
    #enable_fargate_fluentbit                     = true
    enable_aws_for_fluentbit = true
    #enable_aws_node_termination_handler          = true
    enable_karpenter = true
    #enable_velero                                = true
    #enable_aws_gateway_api_controller            = true
    #enable_aws_secrets_store_csi_driver_provider = true
  }
  oss_addons = {
    #enable_argo_rollouts                         = true
    #enable_argo_workflows                        = true
    #enable_cluster_proportional_autoscaler       = true
    #enable_gatekeeper                            = true
    #enable_gpu_operator                          = true
    enable_ingress_nginx = true
    enable_kyverno       = true
    #enable_kube_prometheus_stack                 = true
    enable_metrics_server = true
    #enable_prometheus_adapter                    = true
    #enable_secrets_store_csi_driver              = true
    #enable_vpa                                   = true
    #enable_foo                                   = true # you can add any addon here, make sure to update the gitops repo with the corresponding application set
  }
  addons = merge(local.aws_addons, local.oss_addons, { kubernetes_version = local.cluster_version })

  #----------------------------------------------------------------
  # GitOps Bridge, define metadatas to pass from Terraform to ArgoCD
  #----------------------------------------------------------------

  addons_metadata = merge(
    try(module.eks_blueprints_addons.gitops_metadata, {}), # eks blueprints addons automatically expose metadatas
    {
      aws_cluster_name = module.eks.cluster_name
      aws_region       = local.region
      aws_account_id   = data.aws_caller_identity.current.account_id
      aws_vpc_id       = data.aws_vpc.vpc.id
      cluster_endpoint = try(module.eks.cluster_endpoint, {})
      env              = local.env
    },
    {
      argocd_password                             = bcrypt(data.aws_secretsmanager_secret_version.admin_password_version.secret_string)
      aws_secret_manager_git_private_ssh_key_name = local.aws_secret_manager_git_private_ssh_key_name

      gitops_workloads_url      = local.gitops_workloads_url
      gitops_workloads_path     = local.gitops_workloads_path
      gitops_workloads_revision = local.gitops_workloads_revision

      addons_repo_url      = local.gitops_addons_url
      addons_repo_basepath = local.gitops_addons_basepath
      addons_repo_path     = local.gitops_addons_path
      addons_repo_revision = local.gitops_addons_revision
    },
    {
      eks_cluster_domain         = local.eks_cluster_domain
      external_dns_policy        = "sync"
      ingress_type               = local.ingress_type
      argocd_route53_weight      = local.argocd_route53_weight
      route53_weight             = local.route53_weight
      ecsfrontend_route53_weight = local.ecsfrontend_route53_weight
      #target_group_arn = local.service == "blue"? data.aws_lb_target_group.tg_blue.arn : data.aws_lb_target_group.tg_green.arn # <-- Add this line
      #      external_lb_dns = data.aws_lb.alb.dns_name
    }
  )

  #---------------------------------------------------------------
  # Manifests for bootstraping the cluster for addons & workloads
  #---------------------------------------------------------------

  argocd_apps = {
    addons    = file("${path.module}/../../bootstrap/addons.yaml")
    workloads = file("${path.module}/../../bootstrap/workloads.yaml")
  }

  tags = {
    Blueprint  = local.name
    GithubRepo = "github.com/aws-ia/terraform-aws-eks-blueprints"
  }

}

# Find the user currently in use by AWS
data "aws_caller_identity" "current" {}

data "aws_vpc" "vpc" {
  filter {
    name   = "tag:Name"
    values = [local.tag_val_vpc]
  }
}

data "aws_subnets" "private" {
  filter {
    name   = "tag:Name"
    values = ["${local.tag_val_private_subnet}*"]
  }
}

#Add Tags for the new cluster in the VPC Subnets
resource "aws_ec2_tag" "private_subnets" {
  for_each    = toset(data.aws_subnets.private.ids)
  resource_id = each.value
  key         = "kubernetes.io/cluster/${local.environment}-${local.service}"
  value       = "shared"
}

data "aws_subnets" "public" {
  filter {
    name   = "tag:Name"
    values = ["${local.tag_val_public_subnet}*"]
  }
}

#Add Tags for the new cluster in the VPC Subnets
resource "aws_ec2_tag" "public_subnets" {
  for_each    = toset(data.aws_subnets.public.ids)
  resource_id = each.value
  key         = "kubernetes.io/cluster/${local.environment}-${local.service}"
  value       = "shared"
}

# Get HostedZone four our deployment
data "aws_route53_zone" "sub" {
  name = "${local.environment}.${local.hosted_zone_name}"
}

################################################################################
# AWS Secret Manager for argocd password
################################################################################

data "aws_secretsmanager_secret" "argocd" {
  name = "${local.argocd_secret_manager_name_suffix}.${local.environment}"
}

data "aws_secretsmanager_secret_version" "admin_password_version" {
  secret_id = data.aws_secretsmanager_secret.argocd.id
}

################################################################################
# EKS Cluster
################################################################################
#tfsec:ignore:aws-eks-enable-control-plane-logging
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "19.15.2"

  cluster_name                   = local.name
  cluster_version                = local.cluster_version
  cluster_endpoint_public_access = false

  vpc_id     = data.aws_vpc.vpc.id
  subnet_ids = data.aws_subnets.private.ids

  #we uses only 1 security group to allow connection with Fargate, MNG, and Karpenter nodes
  create_node_security_group = false
  eks_managed_node_groups = {
    initial = {
      node_group_name = local.node_group_name
      instance_types  = ["m5.large"]

      min_size     = 1
      max_size     = 5
      desired_size = 3
      subnet_ids   = data.aws_subnets.private.ids
    }
  }

  manage_aws_auth_configmap = true
  aws_auth_roles = concat(
    [for team in module.eks_blueprints_dev_teams : team.aws_auth_configmap_role],
    [
      module.eks_blueprints_platform_teams.aws_auth_configmap_role,
      {
        rolearn  = module.eks_blueprints_addons.karpenter.node_iam_role_arn
        username = "system:node:{{EC2PrivateDNSName}}"
        groups = [
          "system:bootstrappers",
          "system:nodes",
        ]
      },
      {
        rolearn  = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${local.eks_admin_role_name}" # The ARN of the IAM role
        username = "ops-role"                                                                                      # The user name within Kubernetes to map to the IAM role
        groups   = ["system:masters"]                                                                              # A list of groups within Kubernetes to which the role is mapped; Checkout K8s Role and Rolebindings
      }
    ]
  )

  tags = merge(local.tags, {
    # NOTE - if creating multiple security groups with this module, only tag the
    # security group that Karpenter should utilize with the following tag
    # (i.e. - at most, only one security group should have this tag in your account)
    "karpenter.sh/discovery" = "${local.environment}-${local.service}"
  })
}

data "aws_iam_role" "eks_admin_role_name" {
  count = local.eks_admin_role_name!= ""? 1 : 0
  name  = local.eks_admin_role_name
}

################################################################################
# EKS Blueprints Teams
################################################################################
module "eks_blueprints_platform_teams" {
  source  = "aws-ia/eks-blueprints-teams/aws@b588484884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884884