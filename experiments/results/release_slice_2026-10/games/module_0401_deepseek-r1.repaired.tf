module "this" {
  source = "git::https://github.com/cloudposse/terraform-null-label.git?ref=488ab39c9a6d1a0e0b0c21803acb5f2319dad26b"

  enabled             = var.enabled
  namespace           = var.namespace
  tenant              = var.tenant
  environment         = var.environment
  stage               = var.stage
  name                = var.name
  delimiter           = var.delimiter
  attributes          = var.attributes
  tags                = var.tags
  additional_tag_map  = var.additional_tag_map
  label_order         = var.label_order
  regex_replace_chars = var.regex_replace_chars
  id_length_limit     = var.id_length_limit
  label_key_case      = var.label_key_case
  label_value_case    = var.label_value_case
  descriptor_formats  = var.descriptor_formats
  labels_as_tags      = var.labels_as_tags

  context = var.context
}

provider "aws" {
  region = var.region
}

module "label" {
  source = "git::https://github.com/cloudposse/terraform-null-label.git?ref=488ab39c9a6d1a0e0b0c21803acb5f2319dad26b"

  attributes = ["cluster"]

  context = module.this.context
}

data "aws_caller_identity" "current" {}

data "aws_iam_session_context" "current" {
  arn = data.aws_caller_identity.current.arn
}

locals {
  enabled = module.this.enabled

  private_ipv6_enabled = var.private_ipv6_enabled

  tags = { "kubernetes.io/cluster/${module.label.id}" = "shared" }

  public_subnets_additional_tags = {
    "kubernetes.io/role/elb" : 1
  }
  private_subnets_additional_tags = {
    "kubernetes.io/role/internal-elb" : 1
  }

  access_entry_map = {
    (data.aws_iam_session_context.current.issuer_arn) = {
      access_policy_associations = {
        ClusterAdmin = {}
      }
    }
  }

  vpc_cni_addon = {
    addon_name               = "vpc-cni"
    addon_version            = null
    resolve_conflicts        = "OVERWRITE"
    service_account_role_arn = one(module.vpc_cni_eks_iam_role[*].service_account_role_arn)
  }

  addons = concat([
    local.vpc_cni_addon
  ], var.addons)
}

module "vpc" {
  source = "git::https://github.com/cloudposse/terraform-aws-vpc.git?ref=3c6b3d0e42d0a9d23f5ef1b0a0c0c0a8c3c1c8c7"

  ipv4_primary_cidr_block = "172.16.0.0/16"
  tags                    = local.tags
  vpc_flow_logs = {
    log_destination_type = "cloud-watch-logs"
    traffic_type         = "REJECT"
  }

  context = module.this.context
}

module "subnets" {
  source = "git::https://github.com/cloudposse/terraform-aws-dynamic-subnets.git?ref=3a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a"

  availability_zones              = var.availability_zones
  vpc_id                          = module.vpc.vpc_id
  igw_id                          = [module.vpc.igw_id]
  ipv4_cidr_block                 = [module.vpc.vpc_cidr_block]
  ipv6_cidr_block                 = [module.vpc.vpc_ipv6_cidr_block]
  ipv6_enabled                    = true
  max_nats                        = 1
  nat_gateway_enabled             = true
  nat_instance_enabled            = false
  tags                            = local.tags
  public_subnets_additional_tags  = local.public_subnets_additional_tags
  private_subnets_enabled         = true
  private_subnets_additional_tags = local.private_subnets_additional_tags

  context = module.this.context
}

module "eks_cluster" {
  source = "../../"

  subnet_ids                   = concat(module.subnets.private_subnet_ids, module.subnets.public_subnet_ids)
  kubernetes_version           = var.kubernetes_version
  oidc_provider_enabled        = var.oidc_provider_enabled
  enabled_cluster_log_types    = var.enabled_cluster_log_types
  cluster_log_retention_period = var.cluster_log_retention_period

  cluster_encryption_config_enabled                         = var.cluster_encryption_config_enabled
  cluster_encryption_config_kms_key_id                      = var.cluster_encryption_config_kms_key_id
  cluster_encryption_config_kms_key_enable_key_rotation     = var.cluster_encryption_config_kms_key_enable_key_rotation
  cluster_encryption_config_kms_key_deletion_window_in_days = var.cluster_encryption_config_kms_key_deletion_window_in_days
  cluster_encryption_config_kms_key_policy                  = var.cluster_encryption_config_kms_key_policy
  cluster_encryption_config_resources                       = var.cluster_encryption_config_resources

  addons                                = local.addons
  addons_depends_on                     = [module.eks_node_group]
  bootstrap_self_managed_addons_enabled = var.bootstrap_self_managed_addons_enabled
  upgrade_policy                        = var.upgrade_policy
  zonal_shift_config                    = var.zonal_shift_config

  access_entry_map = local.access_entry_map
  access_config = {
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = false
  }

  allowed_security_group_ids = [module.vpc.vpc_default_security_group_id]
  allowed_cidr_blocks        = [module.vpc.vpc_cidr_block]

  kubernetes_network_ipv6_enabled = local.private_ipv6_enabled

  remote_network_config = var.remote_network_config

  context = module.this.context

  cluster_depends_on = [module.subnets]
}

module "eks_node_group" {
  source = "git::https://github.com/cloudposse/terraform-aws-eks-node-group.git?ref=3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b"

  subnet_ids        = local.enabled ? module.subnets.public_subnet_ids : ["filler_string_for_enabled_is_false"]
  cluster_name      = module.eks_cluster.eks_cluster_id
  ami_type          = var.ami_type
  instance_types    = var.instance_types
  desired_size      = var.desired_size
  min_size          = var.min_size
  max_size          = var.max_size
  kubernetes_labels = var.kubernetes_labels
  kubernetes_version = local.enabled ? null : [var.kubernetes_version]

  context = module.this.context
}

data "aws_iam_policy_document" "vpc_cni_ipv6" {
  count = local.vpc_cni_sa_needed ? 1 : 0

  statement {
    sid       = "DescribeResources"
    effect    = "Allow"
    resources = ["*"]
    actions = [
      "ec2:DescribeInstances",
      "ec2:DescribeTags",
      "ec2:DescribeNetworkInterfaces",
      "ec2:DescribeInstanceTypes"
    ]
  }

  statement {
    sid       = "AssignIPv6"
    effect    = "Allow"
    resources = ["arn:aws:ec2:*:*:network-interface/*"]
    actions   = ["ec2:AssignIpv6Addresses"]
  }

  statement {
    sid       = "CreateTags"
    effect    = "Allow"
    resources = ["arn:aws:ec2:*:*:network-interface/*"]
    actions   = ["ec2:CreateTags"]
  }
}

module "vpc_cni_eks_iam_role" {
  source = "git::https://github.com/cloudposse/terraform-aws-eks-iam-role.git?ref=4c4c4c4c4c4c4c4c4c4c4c4c4c4c4c4c4c4c4c4c4"

  enabled = local.vpc_cni_sa_needed

  eks_cluster_oidc_issuer_url = module.eks_cluster.eks_cluster_identity_oidc_issuer

  service_account_name      = "aws-node"
  service_account_namespace = "kube-system"

  aws_iam_policy_document = try([data.aws_iam_policy_document.vpc_cni_ipv6[0].json], [])

  context = module.this.context
}

# Remaining code unchanged...