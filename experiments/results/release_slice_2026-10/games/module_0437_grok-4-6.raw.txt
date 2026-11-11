locals {
  # If you have custom addons, create a file called `additional-addon-support_override.tf`
  # and in that file override any of the following declarations as needed.


  # Set `overridable_deploy_additional_addons_to_fargate` to indicate whether or not
  # there are custom addons that should be deployed to Fargate on nodeless clusters.
  overridable_deploy_additional_addons_to_fargate = false

  # `overridable_additional_addon_service_account_role_arn_map` is a map of addon names
  # to the service account role ARNs they use.
  # See the README for more details.
  overridable_additional_addon_service_account_role_arn_map = {
    # Example:
    # my-addon = module.my_addon_eks_iam_role.service_account_role_arn
  }

  # If you are creating Fargate profiles for your addons,
  # use "cloudposse/eks-fargate-profile/aws" to create them
  # and set `overridable_additional_addon_fargate_profiles` to a map of addon names
  # to the corresponding eks-fargate-profile module output.
  overridable_additional_addon_fargate_profiles = {
    # Example:
    # my-addon = module.my_addon_fargate_profile
  }

  # If you have additional dependencies that must be created before the addons are deployed,
  # override this declaration by creating a file called `additional-addon-support_override.tf`
  # and setting `overridable_addons_depends_on` appropriately.
  overridable_addons_depends_on = []
}


# https://docs.aws.amazon.com/eks/latest/userguide/eks-add-ons.html
# https://docs.aws.amazon.com/eks/latest/userguide/managing-add-ons.html#creating-an-add-on

locals {
  eks_cluster_oidc_issuer_url = local.enabled ? replace(module.eks_cluster.eks_cluster_identity_oidc_issuer, "https://", "") : ""
  eks_cluster_id              = local.enabled ? module.eks_cluster.eks_cluster_id : ""

  addon_names                = [for k, v in var.addons : k if v.enabled]
  vpc_cni_addon_enabled      = local.enabled && contains(local.addon_names, "vpc-cni")
  aws_ebs_csi_driver_enabled = local.enabled && contains(local.addon_names, "aws-ebs-csi-driver")
  aws_efs_csi_driver_enabled = local.enabled && contains(local.addon_names, "aws-efs-csi-driver")
  coredns_enabled            = local.enabled && contains(local.addon_names, "coredns")

  # The `vpc-cni`, `aws-ebs-csi-driver`, and `aws-efs-csi-driver` addons are special as they always require an
  # IAM role for Kubernetes Service Account (IRSA). The roles are created by this component unless ARNs are provided.
  # Use "?" operator to avoid evaluating map lookup when entry is missing
  vpc_cni_sa_needed = local.vpc_cni_addon_enabled ? lookup(var.addons["vpc-cni"], "service_account_role_arn", null) == null : false
  ebs_csi_sa_needed = local.aws_ebs_csi_driver_enabled ? lookup(var.addons["aws-ebs-csi-driver"], "service_account_role_arn", null) == null : false
  efs_csi_sa_needed = local.aws_efs_csi_driver_enabled ? lookup(var.addons["aws-efs-csi-driver"], "service_account_role_arn", null) == null : false
  addon_service_account_role_arn_map = {
    vpc-cni            = module.vpc_cni_eks_iam_role.service_account_role_arn
    aws-ebs-csi-driver = module.aws_ebs_csi_driver_eks_iam_role.service_account_role_arn
    aws-efs-csi-driver = module.aws_efs_csi_driver_eks_iam_role.service_account_role_arn
  }

  final_addon_service_account_role_arn_map = merge(local.addon_service_account_role_arn_map, local.overridable_additional_addon_service_account_role_arn_map)

  addons = [
    for k, v in var.addons : {
      addon_name                  = k
      addon_version               = lookup(v, "addon_version", null)
      configuration_values        = lookup(v, "configuration_values", null)
      resolve_conflicts_on_create = lookup(v, "resolve_conflicts_on_create", null)
      resolve_conflicts_on_update = lookup(v, "resolve_conflicts_on_update", null)
      service_account_role_arn    = try(coalesce(lookup(v, "service_account_role_arn", null), lookup(local.final_addon_service_account_role_arn_map, k, null)), null)
      create_timeout              = lookup(v, "create_timeout", null)
      update_timeout              = lookup(v, "update_timeout", null)
      delete_timeout              = lookup(v, "delete_timeout", null)

    } if v.enabled
  ]

  addons_depends_on = concat([
    module.vpc_cni_eks_iam_role,
    module.coredns_fargate_profile,
    module.aws_ebs_csi_driver_eks_iam_role,
    module.aws_ebs_csi_driver_fargate_profile,
    module.aws_efs_csi_driver_eks_iam_role,
  ], local.overridable_addons_depends_on)

  addons_require_fargate = var.deploy_addons_to_fargate && (
    local.coredns_enabled ||
    local.aws_ebs_csi_driver_enabled ||
    # as of EFS add-on v1.5.8, it cannot be deployed to Fargate
    # local.aws_efs_csi_driver_enabled ||
    local.overridable_deploy_additional_addons_to_fargate
  )
  addon_fargate_profiles = merge(
    (local.coredns_enabled && var.deploy_addons_to_fargate ? {
      coredns = one(module.coredns_fargate_profile[*])
    } : {}),
    (local.aws_ebs_csi_driver_enabled && var.deploy_addons_to_fargate ? {
      aws_ebs_csi_driver = one(module.aws_ebs_csi_driver_fargate_profile[*])
    } : {}),
    # as of EFS add-on v1.5.8, it cannot be deployed to Fargate
    # See https://github.com/kubernetes-sigs/aws-efs-csi-driver/issues/1100
    #    (local.aws_efs_csi_driver_enabled && var.deploy_addons_to_fargate ? {
    #      aws_efs_csi_driver = one(module.aws_efs_csi_driver_fargate_profile[*])
    #    } : {}),
    local.overridable_additional_addon_fargate_profiles
  )
}

# `vpc-cni` EKS addon
# https://docs.aws.amazon.com/eks/latest/userguide/cni-iam-role.html
# https://docs.aws.amazon.com/eks/latest/userguide/managing-vpc-cni.html
# https://docs.aws.amazon.com/eks/latest/userguide/cni-iam-role.html#cni-iam-role-create-role
# https://aws.github.io/aws-eks-best-practices/networking/vpc-cni/#deploy-vpc-cni-managed-add-on
data "aws_iam_policy_document" "vpc_cni_ipv6" {
  count = local.vpc_cni_sa_needed ? 1 : 0

  # See https://docs.aws.amazon.com/eks/latest/userguide/cni-iam-role.html#cni-iam-role-create-ipv6-policy
  statement {
    sid       = ""
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
    sid       = ""
    effect    = "Allow"
    resources = ["arn:aws:ec2:*:*:network-interface/*"]

    actions = [
      "ec2:AssignIpv6Addresses"
    ]
  }

  statement {
    sid       = ""
    effect    = "Allow"
    resources = ["arn:aws:ec2:*:*:network-interface/*"]
    actions   = ["ec2:CreateTags"]
  }
}

resource "aws_iam_role_policy_attachment" "vpc_cni" {
  count = local.vpc_cni_sa_needed ? 1 : 0

  role       = module.vpc_cni_eks_iam_role.service_account_role_name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

module "vpc_cni_eks_iam_role" {
  source = "git::https://github.com/cloudposse/terraform-aws-eks-iam-role.git?ref=79d1bb8bb110a80534180d0c7aae1a116468cd0d"

  enabled = local.vpc_cni_sa_needed

  eks_cluster_oidc_issuer_url = local.eks_cluster_oidc_issuer_url

  service_account_name      = "aws-node"
  service_account_namespace = "kube-system"

  aws_iam_policy_document = [one(data.aws_iam_policy_document.vpc_cni_ipv6[*].json)]

  context = module.this.context
}

module "coredns_fargate_profile" {
  count = local.coredns_enabled && var.deploy_addons_to_fargate ? 1 : 0

  source = "git::https://github.com/cloudposse/terraform-aws-eks-fargate-profile.git?ref=90c4c70dcab017d78342d72e3875db1c34633b00"

  subnet_ids                              = local.private_subnet_ids
  cluster_name                            = local.eks_cluster_id
  kubernetes_namespace                    = "kube-system"
  kubernetes_labels                       = { k8s-app = "kube-dns" }
  permissions_boundary                    = var.fargate_profile_iam_role_permissions_boundary
  iam_role_kubernetes_namespace_delimiter = var.fargate_profile_iam_role_kubernetes_namespace_delimiter

  fargate_profile_name               = "${local.eks_cluster_id}-coredns"
  fargate_pod_execution_role_enabled = false
  fargate_pod_execution_role_arn     = one(module.fargate_pod_execution_role[*].eks_fargate_pod_execution_role_arn)

  attributes = ["coredns"]
  context    = module.this.context
}

# `aws-ebs-csi-driver` EKS addon
# https://docs.aws.amazon.com/eks/latest/userguide/csi-iam-role.html
# https://aws.amazon.com/blogs/containers/amazon-ebs-csi-driver-is-now-generally-available-in-amazon-eks-add-ons
# https://docs.aws.amazon.com/eks/latest/userguide/managing-ebs-csi.html#csi-iam-role
# https://github.com/kubernetes-sigs/aws-ebs-csi-driver
resource "aws_iam_role_policy_attachment" "aws_ebs_csi_driver" {
  count = local.ebs_csi_sa_needed ? 1 : 0

  role       = module.aws_ebs_csi_driver_eks_iam_role.service_account_role_name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

module "aws_ebs_csi_driver_eks_iam_role" {
  source = "git::https://github.com/cloudposse/terraform-aws-eks-iam-role.git?ref=79d1bb8bb110a80534180