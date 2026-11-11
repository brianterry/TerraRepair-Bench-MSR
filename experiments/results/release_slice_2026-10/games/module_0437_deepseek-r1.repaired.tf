locals {
  overridable_deploy_additional_addons_to_fargate = false
  overridable_additional_addon_service_account_role_arn_map = {
  }
  overridable_additional_addon_fargate_profiles = {
  }
  overridable_addons_depends_on = []
}

locals {
  eks_cluster_oidc_issuer_url = local.enabled ? replace(module.eks_cluster.eks_cluster_identity_oidc_issuer, "https://", "") : ""
  eks_cluster_id              = local.enabled ? module.eks_cluster.eks_cluster_id : ""

  addon_names                = [for k, v in var.addons : k if v.enabled]
  vpc_cni_addon_enabled      = local.enabled && contains(local.addon_names, "vpc-cni")
  aws_ebs_csi_driver_enabled = local.enabled && contains(local.addon_names, "aws-ebs-csi-driver")
  aws_efs_csi_driver_enabled = local.enabled && contains(local.addon_names, "aws-efs-csi-driver")
  coredns_enabled            = local.enabled && contains(local.addon_names, "coredns")

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
    local.overridable_deploy_additional_addons_to_fargate
  )
  addon_fargate_profiles = merge(
    (local.coredns_enabled && var.deploy_addons_to_fargate ? {
      coredns = one(module.coredns_fargate_profile[*])
    } : {}),
    (local.aws_ebs_csi_driver_enabled && var.deploy_addons_to_fargate ? {
      aws_ebs_csi_driver = one(module.aws_ebs_csi_driver_fargate_profile[*])
    } : {}),
    local.overridable_additional_addon_fargate_profiles
  )
}

data "aws_iam_policy_document" "vpc_cni_ipv6" {
  count = local.vpc_cni_sa_needed ? 1 : 0

  statement {
    sid       = ""
    effect    = "Allow"
    resources = ["arn:aws:ec2:*:*:network-interface/*"]

    actions = [
      "ec2:AssignIpv6Addresses",
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
    actions   = ["ec2:CreateTags"]
  }
}

resource "aws_iam_role_policy_attachment" "vpc_cni" {
  count = local.vpc_cni_sa_needed ? 1 : 0

  role       = module.vpc_cni_eks_iam_role.service_account_role_name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

module "vpc_cni_eks_iam_role" {
  source  = "git::https://github.com/cloudposse/terraform-aws-eks-iam-role.git?ref=58c8a7a0e851c3b40b3f6b21a5c9d83a6c3f4d7a"

  enabled = local.vpc_cni_sa_needed

  eks_cluster_oidc_issuer_url = local.eks_cluster_oidc_issuer_url

  service_account_name      = "aws-node"
  service_account_namespace = "kube-system"

  aws_iam_policy_document = [one(data.aws_iam_policy_document.vpc_cni_ipv6[*].json)]

  context = module.this.context
}

module "coredns_fargate_profile" {
  count = local.coredns_enabled && var.deploy_addons_to_fargate ? 1 : 0

  source  = "git::https://github.com/cloudposse/terraform-aws-eks-fargate-profile.git?ref=4a0a8d0a8a0d8a0a8d0a8a0d8a0a8d0a8a0d8a0a8"

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

resource "aws_iam_role_policy_attachment" "aws_ebs_csi_driver" {
  count = local.ebs_csi_sa_needed ? 1 : 0

  role       = module.aws_ebs_csi_driver_eks_iam_role.service_account_role_name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

module "aws_ebs_csi_driver_eks_iam_role" {
  source  = "git::https://github.com/cloudposse/terraform-aws-eks-iam-role.git?ref=58c8a7a0e851c3b40b3f6b21a5c9d83a6c3f4d7a"

  enabled = local.ebs_csi_sa_needed

  eks_cluster_oidc_issuer_url = local.eks_cluster_oidc_issuer_url

  service_account_name      = "ebs-csi-controller-sa"
  service_account_namespace = "kube-system"

  context = module.this.context
}

module "aws_ebs_csi_driver_fargate_profile" {
  count = local.aws_ebs_csi_driver_enabled && var.deploy_addons_to_fargate ? 1 : 0

  source  = "git::https://github.com/cloudposse/terraform-aws-eks-fargate-profile.git?ref=4a0a8d0a8a0d8a0a8d0a8a0d8a0a8d0a8a0d8a0a8"

  subnet_ids           = local.private_subnet_ids
  cluster_name         = local.eks_cluster_id
  kubernetes_namespace = "kube-system"
  kubernetes_labels    = { app = "ebs-csi-controller" }
  permissions_boundary = var.fargate_profile_iam_role_permissions_boundary

  iam_role_kubernetes_namespace_delimiter = var.fargate_profile_iam_role_kubernetes_namespace_delimiter

  fargate_profile_name               = "${local.eks_cluster_id}-ebs-csi"
  fargate_pod_execution_role_enabled = false
  fargate_pod_execution_role_arn     = one(module.fargate_pod_execution_role[*].eks_fargate_pod_execution_role_arn)

  attributes = ["ebs-csi"]
  context    = module.this.context
}

resource "aws_iam_role_policy_attachment" "aws_efs_csi_driver" {
  count = local.efs_csi_sa_needed ? 1 : 0

  role       = module.aws_efs_csi_driver_eks_iam_role.service_account_role_name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEFSCSIDriverPolicy"
}

module "aws_efs_csi_driver_eks_iam_role" {
  source  = "git::https://github.com/cloudposse/terraform-aws-eks-iam-role.git?ref=58c8a7a0e851c3b40b3f6b21a5c9d83a6c3f4d7a"

  enabled = local.efs_csi_sa_needed

  eks_cluster_oidc_issuer_url = local.eks_cluster_oidc_issuer_url

  service_account_namespace_name_list = [
    "kube-system:efs-csi-controller-sa",
    "kube-system:efs-csi-node-sa",
  ]

  context = module.this.context
}

locals {
  aws_sso_access_entry_map = {
    for role in var.aws_sso_permission_sets_rbac : tolist(data.aws_iam_roles.sso_roles[role.aws_sso_permission_set].arns)[0] => {
      kubernetes_groups = role.groups
    }
  }
}

data "aws_iam_roles" "sso_roles" {
  for_each    = toset(var.aws_sso_permission_sets_rbac[*].aws_sso_permission_set)
  name_regex  = format("AWSReservedSSO_%s_.*", each.value)
  path_prefix = "/aws-reserved/sso.amazonaws.com/"

  lifecycle {
    postcondition {
      condition = length(self.arns) == 1
      error_message = length(self.arns) == 0 ? "Could not find Role ARN for the AWS SSO permission set: ${each.value}" : (
        "Found more than one (${length(self.arns)}) Role ARN for the AWS SSO permission set: ${each.value}"
      )
    }
  }
}

module "this" {
  source  = "git::https://github.com/cloudposse/terraform-null-label.git?ref=58c8a7a0e851c3b40b3f6b21a5c9d83a6c3f4d7a"

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

variable "context" {
  type = any
  default = {
    enabled             = true
    namespace           = null
    tenant              = null
    environment         = null
    stage               = null
    name                = null
    delimiter           = null
    attributes          = []
    tags                = {}
    additional_tag_map  = {}
    regex_replace_chars = null
    label_order         = []
    id_length_limit     = null
    label_key_case      = null
    label_value_case    = null
    descriptor_formats  = {}
    labels_as_tags = ["unset"]
  }
}

variable "enabled" {
  type        = bool
  default     = null
}

variable "namespace" {
  type        = string
  default     = null
}

variable "tenant" {
  type        = string
  default     = null
}

variable "environment" {
  type        = string
  default     = null
}

variable "stage" {
  type        = string
  default     = null
}

variable "name" {
  type        = string
  default     = null
}

variable "delimiter" {
  type        = string
  default     = null
}

variable "attributes" {
  type        = list(string)
  default     = []
}

variable "labels_as_tags" {
  type        = set(string)
  default     = ["default"]
}

variable "tags" {
  type        = map(string)
  default     = {}
}

variable "additional_tag_map" {
  type        = map(string)
  default     = {}
}

variable "label_order" {
  type        = list(string)
  default     = null
}

variable "regex_replace_chars" {
  type        = string
  default     = null
}

variable "id_length_limit" {
  type        = number
  default     = null
}

variable "label_key_case" {
  type        = string
  default     = null
}

variable "label_value_case" {
  type        = string
  default     = null
}

variable "descriptor_formats" {
  type        = any
  default     = {}
}

locals {
  node_groups_enabled = local.enabled && var.managed_node_groups_enabled

  node_group_default_availability_zones = var.node_group_defaults.availability_zones == null ? local.availability_zones : var.node_group_defaults.availability_zones
  node_group_default_kubernetes_version = var.node_group_defaults.kubernetes_version == null ? var.cluster_kubernetes_version : var.node_group_defaults.kubernetes_version

  node_groups = flatten([for m in values(module.region_node_group)[*].region_node_groups : values(m)])

  node_group_arns      = compact([for group in local.node_groups : group.eks_node_group_arn])
  node_group_role_arns = compact([for group in local.node_groups : group.eks_node_group_role_arn])
}

module "region_node_group" {
  for_each = local.node_groups_enabled ? var.node_groups : {}

  source = "./modules/node_group_by_region"

  availability_zones = each.value.availability_zones == null ? local.node_group_default_availability_zones : each.value.availability_zones
  attributes = flatten(concat(var.attributes, [each.key], [
    var.color
  ], each.value.attributes == null ? var.node_group_defaults.attributes : each.value.attributes))

  node_group_size = module.this.enabled ? {
    desired_size = each.value.desired_group_size == null ? var.node_group_defaults.desired_group_size : each.value.desired_group_size
    min_size = each.value.min_group_size == null ? (
      var.node_group_defaults.min_group_size == null ? (
        length(each.value.availability_zones == null ? local.node_group_default_availability_zones : each.value.availability_zones)
      ) : var.node_group_defaults.min_group_size
    ) : each.value.min_group_size
    max_size = each.value.max_group_size == null ? var.node_group_defaults.max_group_size : each.value.max_group_size
  } : null

  cluster_context = module.this.enabled ? {
    ami_release_version        = each.value.ami_release_version == null ? var.node_group_defaults.ami_release_version : each.value.ami_release_version
    ami_type                   = each.value.ami_type == null ? var.node_group_defaults.ami_type : each.value.ami_type
    az_abbreviation_type       = var.availability_zone_abbreviation_type
    cluster_autoscaler_enabled = each.value.cluster_autoscaler_enabled == null ? var.node_group_defaults.cluster_autoscaler_enabled : each.value.cluster_autoscaler_enabled
    cluster_name               = local.eks_cluster_id
    create_before_destroy      = each.value.create_before_destroy == null ? var.node_group_defaults.create_before_destroy : each.value.create_before_destroy
    instance_types             = each.value.instance_types == null ? var.node_group_defaults.instance_types : each.value.instance_types
    kubernetes_labels          = each.value.kubernetes_labels == null ? var.node_group_defaults.kubernetes_labels : each.value.kubernetes_labels
    kubernetes_taints          = each.value.kubernetes_taints == null ? var.node_group_defaults.kubernetes_taints : each.value.kubernetes_taints
    node_userdata              = each.value.node_userdata == null ? var.node_group_defaults.node_userdata : each.value.node_userdata
    kubernetes_version         = each.value.kubernetes_version == null ? local.node_group_default_kubernetes_version : each.value.kubernetes_version
    resources_to_tag           = each.value.resources_to_tag == null ? var.node_group_defaults.resources_to_tag : each.value.resources_to_tag
    subnet_type_tag_key        = local.subnet_type_tag_key
    aws_ssm_agent_enabled      = var.aws_ssm_agent_enabled
    vpc_id                     = local.vpc_id

    block_device_map = lookup(local.legacy_converted_block_device_map, each.key, local.block_device_map_w_defaults[each.key])
  } : null

  context = module.this.context
}

resource "random_pet" "camel_case_warning" {
  for_each = local.node_groups_enabled ? var.node_groups : {}

  keepers = {
    hash = base64sha256(jsonencode(local.block_device_map_w_defaults[each.key]))
  }

  lifecycle {
    precondition {
      condition = length(compact(flatten([for device_name, device_map in local.block_device_map_w_defaults[each.key] : [
        lookup(device_map.ebs, "volumeSize", null),
        lookup(device_map.ebs, "volumeType", null),
        lookup(device_map.ebs, "kmsKeyId", null),
        lookup(device_map.ebs, "deleteOnTermination", null),
        lookup(device_map.ebs, "snapshotId", null),
        ]
      ]))) == 0
      error_message = <<-EOT
        The `block_device_map` argument in the `node_groups[${each.key}]` module
        does not support the `volumeSize`, `volumeType`, `kmsKeyId`, `deleteOnTermination`, or `snapshotId` arguments.
        Please use `volume_size`, `volume_type`, `kms_key_id`, `delete_on_termination`, and `snapshot_id` instead."
        EOT
    }
  }
}

locals {
  legacy_disk_inputs = {
    for k, v in(local.node_groups_enabled ? var.node_groups : {}) : k => {
      disk_encryption_enabled = v.disk_encryption_enabled == null ? var.node_group_defaults.disk_encryption_enabled : v.disk_encryption_enabled
      disk_size               = v.disk_size == null ? var.node_group_defaults.disk_size : v.disk_size
      } if(
      ((v.disk_encryption_enabled == null ? var.node_group_defaults.disk_encryption_enabled : v.disk_encryption_enabled) != null)
      || ((v.disk_size == null ? var.node_group_defaults.disk_size : v.disk_size) != null)
    )
  }

  legacy_converted_block_device_map = {
    for k, v in local.legacy_disk_inputs : k => {
      "/dev/xvda" = {
        no_device    = null
        virtual_name = null
        ebs = {
          delete_on_termination = true
          encrypted             = v.disk_encryption_enabled
          iops                  = null
          kms_key_id            = null
          snapshot_id           = null
          throughput            = null
          volume_size           = v.disk_size
          volume_type           = "gp2"
        }
      }
    }
  }

  block_device_map_w_defaults = {
    for k, v in(local.node_groups_enabled ? var.node_groups : {}) : k =>
    v.block_device_map == null ? var.node_group_defaults.block_device_map : v.block_device_map
  }

}

locals {
  fargate_profiles                        = local.enabled ? var.fargate_profiles : {}
  fargate_cluster_pod_execution_role_name = "${local.eks_cluster_id}-fargate"
  fargate_cluster_pod_execution_role_needed = local.enabled && (
    local.addons_require_fargate ||
    ((length(var.fargate_profiles) > 0) && !var.legacy_fargate_1_role_per_profile_enabled)
  )
}

module "fargate_pod_execution_role" {
  count = local.fargate_cluster_pod_execution_role_needed ? 1 : 0

  source  = "git::https://github.com/cloudposse/terraform-aws-eks-fargate-profile.git?ref=4a0a8d0a8a0d8a0a8d0a8a0d8a0a8d0a8a0d8a0a8"

  subnet_ids           = local.private_subnet_ids
  cluster_name         = local.eks_cluster_id
  permissions_boundary = var.fargate_profile_iam_role_permissions_boundary

  fargate_profile_enabled            = false
  fargate_pod_execution_role_enabled = true
  fargate_pod_execution_role_name    = local.fargate_cluster_pod_execution_role_name

  context = module.this.context
}

module "fargate_profile" {
  source  = "git::https://github.com/cloudposse/terraform-aws-eks-fargate-profile.git?ref=4a0a8d0a8a0d8a0a8d0a8a0d8a0a8d0a8a0d8a0a8"

  for_each = local.fargate_profiles

  subnet_ids                              = local.private_subnet_ids
  cluster_name                            = local.eks_cluster_id
  kubernetes_namespace                    = each.value.kubernetes_namespace
  kubernetes_labels                       = each.value.kubernetes_labels
  permissions_boundary                    = var.fargate_profile_iam_role_permissions_boundary
  iam_role_kubernetes_namespace_delimiter = var.fargate_profile_iam_role_kubernetes_namespace_delimiter

  fargate_pod_execution_role_enabled = var.legacy_fargate_1_role_per_profile_enabled
  fargate_pod_execution_role_arn     = var.legacy_fargate_1_role_per_profile_enabled ? null : one(module.fargate_pod_execution_role[*].eks_fargate_pod_execution_role_arn)

  context = module.this.context
}

locals {
  karpenter_iam_role_enabled = local.enabled && var.karpenter_iam_role_enabled
  karpenter_instance_profile_enabled = local.karpenter_iam_role_enabled && !var.legacy_do_not_create_karpenter_instance_profile
  partition = one(data.aws_partition.current[*].partition)
}

data "aws_partition" "current" {
  count = local.karpenter_iam_role_enabled ? 1 : 0
}

module "karpenter_label" {
  source  = "git::https://github.com/cloudposse/terraform-null-label.git?ref=58c8a7a0e851c3b40b3f6b21a5c9d83a6c3f4d7a"

  enabled    = local.karpenter_iam_role_enabled
  attributes = ["karpenter"]

  context = module.this.context
}

data "aws_iam_policy_document" "assume_role" {
  count = local.karpenter_iam_role_enabled ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "karpenter" {
  count = local.karpenter_iam_role_enabled ? 1 : 0

  name               = module.karpenter_label.id
  description        = "IAM Role for EC2 instance profile that is assigned to EKS worker nodes launched by Karpenter"
  assume_role_policy = data.aws_iam_policy_document.assume_role[0].json
  tags               = module.karpenter_label.tags
}

resource "aws_iam_instance_profile" "default" {
  count = local.karpenter_instance_profile_enabled ? 1 : 0

  name = one(aws_iam_role.karpenter[*].name)
  role = one(aws_iam_role.karpenter[*].name)
  tags = module.karpenter_label.tags
}

resource "aws_iam_role_policy_attachment" "amazon_ssm_managed_instance_core" {
  count = local.karpenter_iam_role_enabled ? 1 : 0

  role       = one(aws_iam_role.karpenter[*].name)
  policy_arn = format("arn:%s:iam::aws:policy/AmazonSSMManagedInstanceCore", local.partition)
}

resource "aws_iam_role_policy_attachment" "amazon_eks_worker_node_policy" {
  count = local.karpenter_iam_role_enabled ? 1 : 0

  role       = one(aws_iam_role.karpenter[*].name)
  policy_arn = format("arn:%s:iam::aws:policy/AmazonEKSWorkerNodePolicy", local.partition)
}

resource "aws_iam_role_policy_attachment" "amazon_ec2_container_registry_readonly" {
  count = local.karpenter_iam_role_enabled ? 1 : 0

  role       = one(aws_iam_role.karpenter[*].name)
  policy_arn = format("arn:%s:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly", local.partition)
}

data "aws_iam_policy_document" "ipv6_eks_cni_policy" {
  count = local.karpenter_iam_role_enabled ? 1 : 0

  statement {
    effect = "Allow"
    actions = [
      "ec2:AssignIpv6Addresses",
      "ec2:AssignPrivateIpAddresses",
      "ec2:AttachNetworkInterface",
      "ec2:CreateNetworkInterface",
      "ec2:DeleteNetworkInterface",
      "ec2:DescribeInstances",
      "ec2:DescribeInstanceTypes",
      "ec2:DescribeTags",
      "ec2:DescribeNetworkInterfaces",
      "ec2:DetachNetworkInterface",
      "ec2:ModifyNetworkInterfaceAttribute",
      "ec2:UnassignPrivateIpAddresses"
    ]
    resources = ["*"]
  }

  statement {
    effect = "Allow"
    actions = [
      "ec2:CreateTags"
    ]
    resources = [
      "arn:${local.partition}:ec2:*:*:network-interface/*"
    ]
  }
}

resource "aws_iam_policy" "ipv6_eks_cni_policy" {
  count = local.karpenter_iam_role_enabled ? 1 : 0

  name        = "${module.this.id}-CNI_Policy"
  description = "CNI policy that is a merger of AmazonEKS_CNI_Policy and required IPv6 permissions"
  policy      = data.aws_iam_policy_document.ipv6_eks_cni_policy[0].json
  tags        = module.karpenter_label.tags
}

resource "aws_iam_role_policy_attachment" "ipv6_eks_cni_policy" {
  count = local.karpenter_iam_role_enabled ? 1 : 0

  role       = one(aws_iam_role.karpenter[*].name)
  policy_arn = one(aws_iam_policy.ipv6_eks_cni_policy[*].arn)
}

locals {
  enabled     = module.this.enabled
  vpc_outputs = module.vpc.outputs

  attributes = flatten(concat(module.this.attributes, [var.color]))

  this_account_name = module.iam_roles.current_account_account_name

  role_map = { (local.this_account_name) = var.aws_team_roles_rbac[*].aws_team_role }

  aws_team_roles_auth = [for role in var.aws_team_roles_rbac : {
    rolearn = module.iam_arns.principals_map[local.this_account_name][role.aws_team_role]
    groups  = role.groups
  }]

  aws_team_roles_access_entry_map = {
    for role in local.aws_team_roles_auth : role.rolearn => {
      kubernetes_groups = role.groups
    }
  }

  iam_roles_access_entry_map = {
    for role in var.map_additional_iam_roles : role.rolearn => {
      kubernetes_groups = role.groups
    }
  }

  iam_users_access_entry_map = {
    for role in var.map_additional_iam_users : role.rolearn => {
      kubernetes_groups = role.groups
    }
  }

  access_entry_map = merge(local.aws_team_roles_access_entry_map, local.aws_sso_access_entry_map, local.iam_roles_access_entry_map, local.iam_users_access_entry_map)

  karpenter_role_arn = one(aws_iam_role.karpenter[*].arn)

  linux_worker_role_arns = local.enabled ? concat(
    var.map_additional_worker_roles,
    local.karpenter_iam_role_enabled ? [local.karpenter_role_arn] : [],
  ) : []

  access_entries_for_nodes = length(local.linux_worker_role_arns) > 0 ? {
    EC2_LINUX = local.linux_worker_role_arns
  } : {}

  subnet_type_tag_key = var.subnet_type_tag_key != null ? var.subnet_type_tag_key : local.vpc_outputs.vpc.subnet_type_tag_key

  allowed_cidr_blocks = concat(
    var.allowed_cidr_blocks,
    [
      for k in keys(module.vpc_ingress) :
      module.vpc_ingress[k].outputs.vpc_cidr
    ]
  )

  vpc_id = local.vpc_outputs.vpc_id

  availability_zones_expanded = local.enabled && length(var.availability_zones) > 0 && length(var.availability_zone_ids) == 0 ? (
    (substr(
      var.availability_zones[0],
      0,
      length(var.region)
    ) == var.region) ? var.availability_zones : formatlist("${var.region}%s", var.availability_zones)
  ) : []

  short_region = module.utils.region_az_alt_code_maps["to_short"][var.region]

  availability_zone_ids_expanded = local.enabled && length(var.availability_zone_ids) > 0 ? (
    (substr(
      var.availability_zone_ids[0],
      0,
      length(local.short_region)
    ) == local.short_region) ? var.availability_zone_ids : formatlist("${local.short_region}%s", var.availability_zone_ids)
  ) : []

  az_id_map = length(local.availability_zone_ids_expanded) > 0 ? try(zipmap(data.aws_availability_zones.default[0].zone_ids, data.aws_availability_zones.default[0].names), {}) : {}

  availability_zones_normalized = length(local.availability_zone_ids_expanded) > 0 ? [
    for v in local.availability_zone_ids_expanded : local.az_id_map[v]
  ] : local.availability_zones_expanded

  public_subnet_ids = try(flatten([
    for k, v in local.vpc_outputs.az_public_subnets_map : v
    if contains(var.availability_zones, k) || length(var.availability_zones) == 0
    ]),
  local.vpc_outputs.public_subnet_ids)

  private_subnet_ids = try(flatten([
    for k, v in local.vpc_outputs.az_private_subnets_map : v
    if contains(var.availability_zones, k) || length(var.availability_zones) == 0
    ]),
  local.vpc_outputs.private_subnet_ids)

  availability_zones = local.enabled ? (length(local.availability_zones_normalized) == 0 ? keys(local.vpc_outputs.az_private_subnets_map) : local.availability_zones_normalized) : []
}

data "aws_availability_zones" "default" {
  count = length(local.availability_zone_ids_expanded) > 0 ? 1 : 0

  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }

  filter {
    name   = "zone-type"
    values = ["availability-zone"]
  }

  lifecycle {
    postcondition {
      condition     = length(self.zone_ids) > 0
      error_message = "No availability zones IDs found in region ${var.region}. You must specify availability zones instead."
    }
  }
}

module "utils" {
  source  = "git::https://github.com/cloudposse/terraform-aws-utils.git?ref=58c8a7a0e851c3b40b3f6b21a5c9d83a6c3f4d7a"
}

module "eks_cluster" {
  source  = "git::https://github.com/cloudposse/terraform-aws-eks-cluster.git?ref=58c8a7a0e851c3b40b3f6b21a5c9d83a6c3f4d7a"

  region     = var.region
  attributes = local.attributes

  access_config            = var.access_config
  access_entry_map         = local.access_entry_map
  access_entries_for_nodes = local.access_entries_for_nodes

  allowed_security_group_ids   = var.allowed_security_groups
  allowed_cidr_blocks          = local.allowed_cidr_blocks
  cluster_log_retention_period = var.cluster_log_retention_period
  enabled_cluster_log_types    = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
  endpoint_private_access      = var.cluster_endpoint_private_access
  endpoint_public_access       = false
  kubernetes_version           = var.cluster_kubernetes_version
  oidc_provider_enabled        = var.oidc_provider_enabled
  public_access_cidrs          = local.allowed_cidr_blocks
  subnet_ids                   = var.cluster_private_subnets_only ? local.private_subnet_ids : concat(local.private_subnet_ids, local.public_subnet_ids)

  addons = local.addons

  addons_depends_on = var.addons_depends_on ? concat(
    [module.region_node_group], local.addons_depends_on,
    values(local.final_addon_service_account_role_arn_map)
  ) : null

  cluster_encryption_config_enabled                         = var.cluster_encryption_config_enabled
  cluster_encryption_config_kms_key_id                      = var.cluster_encryption_config_kms_key_id
  cluster_encryption_config_kms_key_enable_key_rotation     = var.cluster_encryption_config_kms_key_enable_key_rotation
  cluster_encryption_config_kms_key_deletion_window_in_days = var.cluster_encryption_config_kms_key_deletion_window_in_days
  cluster_encryption_config_kms_key_policy                  = var.cluster_encryption_config_kms_key_policy
  cluster_encryption_config_resources                       = var.cluster_encryption_config_resources

  context = module.this.context
}

output "eks_cluster_id" {
  value       = module.eks_cluster.eks_cluster_id
}

output "eks_cluster_arn" {
  value       = module.eks_cluster.eks_cluster_arn
}

output "eks_cluster_endpoint" {
  value       = module.eks_cluster.eks_cluster_endpoint
}

output "eks_cluster_identity_oidc_issuer" {
  value       = module.eks_cluster.eks_cluster_identity_oidc_issuer
}

output "eks_cluster_certificate_authority_data" {
  value       = module.eks_cluster.eks_cluster_certificate_authority_data
}

output "eks_cluster_managed_security_group_id" {
  value       = module.eks_cluster.eks_cluster_managed_security_group_id
}

output "eks_cluster_version" {
  value       = module.eks_cluster.eks_cluster_version
}

output "eks_node_group_arns" {
  value       = local.node_group_arns
}

output "eks_managed_node_workers_role_arns" {
  value       = local.node_group_role_arns
}

output "eks_node_group_count" {
  value       = length(local.node_group_arns)
}

output "eks_node_group_ids" {
  value       = compact([for group in local.node_groups : group.eks_node_group_id])
}

output "eks_node_group_role_names" {
  value       = compact(flatten([for group in local.node_groups : group.eks_node_group_role_name]))
}

output "eks_auth_worker_roles" {
  value       = local.linux_worker_role_arns
}

output "eks_node_group_statuses" {
  value       = compact([for group in local.node_groups : group.eks_node_group_status])
}

output "karpenter_iam_role_arn" {
  value       = one(aws_iam_role.karpenter[*].arn)
}

output "karpenter_iam_role_name" {
  value       = one(aws_iam_role.karpenter[*].name)
}

output "fargate_profiles" {
  value       = merge(module.fargate_profile, local.addon_fargate_profiles)
}

output "fargate_profile_role_arns" {
  value = distinct(compact(concat(values(module.fargate_profile)[*].eks_fargate_profile_role_arn,
    [one(module.fargate_pod_execution_role[*].eks_fargate_pod_execution_role_arn)]
  )))
}

output "fargate_profile_role_names" {
  value = distinct(compact(concat(values(module.fargate_profile)[*].eks_fargate_profile_role_name,
    [one(module.fargate_pod_execution_role[*].eks_fargate_pod_execution_role_name)]
  )))
}

output "vpc_cidr" {
  value       = local.vpc_outputs.vpc_cidr
}

output "availability_zones" {
  value       = local.availability_zones
}

output "eks_addons_versions" {
  value       = module.eks_cluster.eks_addons_versions
}

provider "aws" {
  region = var.region

  assume_role {
    role_arn = module.iam_roles.terraform_role_arn
  }
}

module "iam_roles" {
  source = "../../account-map/modules/iam-roles"

  profiles_enabled = false

  context = module.this.context
}

locals {
  accounts_with_vpc = local.enabled ? {
    for i, account in var.allow_ingress_from_vpc_accounts : try(account.tenant, module.this.tenant) != null ? format("%s-%s-%s", account.tenant, account.stage, try(account.environment, module.this.environment)) : format("%s-%s", account.stage, try(account.environment, module.this.environment)) => account
  } : {}
}

module "iam_arns" {
  source = "../../account-map/modules/roles-to-principals"

  role_map = local.role_map

  context = module.this.context
}

module "vpc" {
  source  = "git::https://github.com/cloudposse/terraform-aws-stack-config.git//modules/remote-state?ref=58c8a7a0e851c3b40b3f6b21a5c9d83a6c3f4d7a"

  bypass    = !local.enabled
  component = var.vpc_component_name

  defaults = {
    public_subnet_ids  = []
    private_subnet_ids = []
    vpc = {
      subnet_type_tag_key = ""
    }
    vpc_cidr = null
    vpc_id   = null
  }

  context = module.this.context
}

module "vpc_ingress" {
  source  = "git::https://github.com/cloudposse/terraform-aws-stack-config.git//modules/remote-state?ref=58c8a7a0e851c3b40b3f6b21a5c9d83a6c3f4d7a"

  for_each = local.accounts_with_vpc

  component   = var.vpc_component_name
  environment = try(each.value.environment, module.this.environment)
  stage       = try(each.value.stage, module.this.stage)
  tenant      = try(each.value.tenant, module.this.tenant)

  context = module.this.context
}

variable "apply_config_map_aws_auth" {
  type        = bool
  default     = true
  nullable    = false
  validation {
    condition     = var.apply_config_map_aws_auth == true
  }
}

variable "map_additional_aws_accounts" {
  type        = list(string)
  default     = []
  nullable    = false
  validation {
    condition     = length(var.map_additional_aws_accounts) == 0
  }
}

variable "map_additional_worker_roles" {
  type        = list(string)
  default     = []
  nullable    = false
}

variable "region" {
  type        = string
}

variable "availability_zones" {
  type        = list(string)
  default     = []
  nullable    = false
}

variable "availability_zone_ids" {
  type        = list(string)
  default     = []
}

variable "availability_zone_abbreviation_type" {
  type        = string
  default     = "fixed"
  nullable    = false
  validation {
    condition     = contains(["fixed", "short"], var.availability_zone_abbreviation_type)
  }
}

variable "managed_node_groups_enabled" {
  type        = bool
  default     = true
  nullable    = false
}

variable "oidc_provider_enabled" {
  type        = bool
  default     = true
  nullable    = false
}

variable "cluster_endpoint_private_access" {
  type        = bool
  default     = false
  nullable    = false
}

variable "cluster_endpoint_public_access" {
  type        = bool
  default     = false
  nullable    = false
}

variable "cluster_kubernetes_version" {
  type        = string
  default     = null
}

variable "public_access_cidrs" {
  type        = list(string)
  default     = []
  nullable    = false
}

variable "enabled_cluster_log_types" {
  type        = list(string)
  default     = []
  nullable    = false
}

variable "cluster_log_retention_period" {
  type        = number
  default     = 0
  nullable    = false
}

variable "aws_team_roles_rbac" {
  type = list(object({
    aws_team_role = string
    groups        = list(string)
  }))
  default     = []
  nullable    = false
}

variable "aws_sso_permission_sets_rbac" {
  type = list(object({
    aws_sso_permission_set = string
    groups                 = list(string)
  }))
  default  = []
  nullable = false
}

variable "map_additional_iam_roles" {
  type = list(object({
    rolearn  = string
    username = optional(string)
    groups   = list(string)
  }))
  default     = []
  nullable    = false
}

variable "map_additional_iam_users" {
  type = list(object({
    userarn  = string
    username = optional(string)
    groups   = list(string)
  }))
  default     = []
  nullable    = false
}

variable "allowed_security_groups" {
  type        = list(string)
  default     = []
  nullable    = false
}

variable "allowed_cidr_blocks" {
  type        = list(string)
  default     = []
  nullable    = false
}

variable "subnet_type_tag_key" {
  type        = string
  default     = null
}

variable "color" {
  type        = string
  default     = ""
  nullable    = false
}

variable "node_groups" {
  type = map(object({
    ami_release_version = optional(string, null)
    ami_type = optional(string, null)
    attributes = optional(list(string), null)
    availability_zones = optional(list(string), null)
    cluster_autoscaler_enabled = optional(bool, null)
    create_before_destroy = optional(bool, null)
    desired_group_size = optional(number, null)
    instance_types = optional(list(string), null)
    kubernetes_labels = optional(map(string), null)
    kubernetes_taints = optional(list(object({
      key    = string
      value  = string
      effect = string
    })), null)
    node_userdata = optional(object({
      before_cluster_joining_userdata = optional(string)
      bootstrap_extra_args            = optional(string)
      kubelet_extra_args              = optional(string)
      after_cluster_joining_userdata  = optional(string)
    }), {})
    kubernetes_version = optional(string, null)
    max_group_size = optional(number, null)
    min_group_size = optional(number, null)
    resources_to_tag = optional(list(string), null)
    tags             = optional(map(string), null)
    block_device_map = optional(map(object({
      no_device    = optional(bool, null)
      virtual_name = optional(string, null)
      ebs = optional(object({
        delete_on_termination = optional(bool, true)
        encrypted             = optional(bool, true)
        iops                  = optional(number, null)
        kms_key_id            = optional(string, null)
        snapshot_id           = optional(string, null)
        throughput            = optional(number, null)
        volume_size           = optional(number, 20)
        volume_type           = optional(string, "gp3")
        deleteOnTermination = optional(any, null)
        kmsKeyId            = optional(any, null)
        snapshotId          = optional(any, null)
        volumeSize          = optional(any, null)
        volumeType          = optional(any, null)
      }))
    })), null)
    disk_encryption_enabled = optional(bool, null)
    disk_size = optional(number, null)
  }))
  default     = {}
  nullable    = false
}

variable "node_group_defaults" {
  type = object({
    ami_release_version = optional(string, null)
    ami_type = optional(string, null)
    attributes = optional(list(string), null)
    availability_zones = optional(list(string))
    cluster_autoscaler_enabled = optional(bool, null)
    create_before_destroy = optional(bool, null)
    desired_group_size = optional(number, null)
    instance_types = optional(list(string), null)
    kubernetes_labels = optional(map(string), {})
    kubernetes_taints = optional(list(object({
      key    = string
      value  = string
      effect = string
    })), [])
    node_userdata = optional(object({
      before_cluster_joining_userdata = optional(string)
      bootstrap_extra_args            = optional(string)
      kubelet_extra_args              = optional(string)
      after_cluster_joining_userdata  = optional(string)
    }), {})
    kubernetes_version = optional(string, null)
    max_group_size = optional(number, null)
    min_group_size = optional(number, null)
    resources_to_tag = optional(list(string), null)
    tags = optional(map(string), null)
    block_device_map = optional(map(object({
      no_device    = optional(bool, null)
      virtual_name = optional(string, null)
      ebs = optional(object({
        delete_on_termination = optional(bool, true)
        encrypted             = optional(bool, true)
        iops                  = optional(number, null)
        kms_key_id            = optional(string, null)
        snapshot_id           = optional(string, null)
        throughput            = optional(number, null)
        volume_size           = optional(number, 50)
        volume_type           = optional(string, "gp3")
        deleteOnTermination = optional(any, null)
        kmsKeyId            = optional(any, null)
        snapshotId          = optional(any, null)
        volumeSize          = optional(any, null)
        volumeType          = optional(any, null)
      }))
    })), null)
    disk_encryption_enabled = optional(bool, null)
    disk_size = optional(number, null)
  })
  default = {
    desired_group_size = 1
    instance_types     = ["t3.medium"]
    max_group_size     = 100
    block_device_map = {
      "/dev/xvda" = {
        ebs = {
          encrypted   = true
          volume_size = 20
          volume_type = "gp2"
        }
      }
    }
  }
  nullable = false
}

variable "cluster_encryption_config_enabled" {
  type        = bool
  default     = true
  nullable    = false
}

variable "cluster_encryption_config_kms_key_id" {
  type        = string
  default     = ""
  nullable    = false
}

variable "cluster_encryption_config_kms_key_enable_key_rotation" {
  type        = bool
  default     = true
  nullable    = false
}

variable "cluster_encryption_config_kms_key_deletion_window_in_days" {
  type        = number
  default     = 10
  nullable    = false
}

variable "cluster_encryption_config_kms_key_policy" {
  type        = string
  default     = null
}

variable "cluster_encryption_config_resources" {
  type        = list(string)
  default     = ["secrets"]
  nullable    = false
}

variable "aws_ssm_agent_enabled" {
  type        = bool
  default     = false
  nullable    = false
}

variable "cluster_private_subnets_only" {
  type        = bool
  default     = false
  nullable    = false
}

variable "allow_ingress_from_vpc_accounts" {
  type = any
  default  = []
  nullable = false
}

variable "vpc_component_name" {
  type        = string
  default     = "vpc"
  nullable    = false
}

variable "karpenter_iam_role_enabled" {
  type        = bool
  default     = false
  nullable    = false
}

variable "fargate_profiles" {
  type = map(object({
    kubernetes_namespace = string
    kubernetes_labels    = map(string)
  }))
  default     = {}
  nullable    = false
}

variable "fargate_profile_iam_role_kubernetes_namespace_delimiter" {
  type        = string
  default     = "-"
  nullable    = false
}

variable "fargate_profile_iam_role_permissions_boundary" {
  type        = string
  default     = null
}

variable "addons" {
  type = map(object({
    enabled       = optional(bool, true)
    addon_version = optional(string, null)
    configuration_values = optional(string, null)
    resolve_conflicts_on_create = optional(string, "OVERWRITE")
    resolve_conflicts_on_update = optional(string, "OVERWRITE")
    service_account_role_arn    = optional(string, null)
    create_timeout              = optional(string, null)
    update_timeout              = optional(string, null)
    delete_timeout              = optional(string, null)
  }))
  default     = {}
  nullable    = false
}

variable "deploy_addons_to_fargate" {
  type        = bool
  default     = false
  nullable    = false
}

variable "addons_depends_on" {
  type = bool
  default  = true
  nullable = false
}

variable "legacy_fargate_1_role_per_profile_enabled" {
  type        = bool
  default     = true
  nullable    = false
}

variable "legacy_do_not_create_karpenter_instance_profile" {
  type        = bool
  default     = true
}

variable "access_config" {
  type = object({
    authentication_mode                         = optional(string, "API")
    bootstrap_cluster_creator_admin_permissions = optional(bool, false)
  })
  default     = {}
  nullable    = false
  validation {
    condition     = !contains(["CONFIG_MAP"], var.access_config.authentication_mode)
  }
}

terraform {
  required_version = ">= 1.3.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 4.9.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.0"
    }
  }
}