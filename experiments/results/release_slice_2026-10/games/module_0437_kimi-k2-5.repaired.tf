```hcl
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
    sid       = "DescribeInstances"
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
    sid    = "CreateNetworkInterface"
    effect = "Allow"
    resources = [
      "arn:aws:ec2:*:*:network-interface/*"
    ]
    actions = [
      "ec2:CreateNetworkInterface",
      "ec2:AttachNetworkInterface",
      "ec2:ModifyNetworkInterfaceAttribute",
      "ec2:DeleteNetworkInterface",
      "ec2:AssignPrivateIpAddresses",
      "ec2:UnassignPrivateIpAddresses"
    ]
  }

  statement {
    sid    = "AssignIpv6Addresses"
    effect = "Allow"
    resources = [
      "arn:aws:ec2:*:*:network-interface/*"
    ]
    actions = [
      "ec2:AssignIpv6Addresses"
    ]
  }

  statement {
    sid       = "CreateTags"
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
  source = "github.com/cloudposse/terraform-aws-eks-iam-role?ref=2.1.1"

  enabled = local.vpc_cni_sa_needed

  eks_cluster_oidc_issuer_url = local.eks_cluster_oidc_issuer_url

  service_account_name      = "aws-node"
  service_account_namespace = "kube-system"

  aws_iam_policy_document = [one(data.aws_iam_policy_document.vpc_cni_ipv6[*].json)]

  context = module.this.context
}

module "coredns_fargate_profile" {
  count = local.coredns_enabled && var.deploy_addons_to_fargate ? 1 : 0

  source = "github.com/cloudposse/terraform-aws-eks-fargate-profile?ref=1.3.0"

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
  source = "github.com/cloudposse/terraform-aws-eks-iam-role?ref=2.1.1"

  enabled = local.ebs_csi_sa_needed

  eks_cluster_oidc_issuer_url = local.eks_cluster_oidc_issuer_url

  service_account_name      = "ebs-csi-controller-sa"
  service_account_namespace = "kube-system"

  context = module.this.context
}

module "aws_ebs_csi_driver_fargate_profile" {
  count = local.aws_ebs_csi_driver_enabled && var.deploy_addons_to_fargate ? 1 : 0

  source = "github.com/cloudposse/terraform-aws-eks-fargate-profile?ref=1.3.0"

  subnet_ids           = local.private_subnet_ids
  cluster_name         = local.eks_cluster_id
  kubernetes_namespace = "kube-system"
  kubernetes_labels    = { app = "ebs-csi-controller" } # Only deploy the controller to Fargate, not the node driver
  permissions_boundary = var.fargate_profile_iam_role_permissions_boundary

  iam_role_kubernetes_namespace_delimiter = var.fargate_profile_iam_role_kubernetes_namespace_delimiter

  fargate_profile_name               = "${local.eks_cluster_id}-ebs-csi"
  fargate_pod_execution_role_enabled = false
  fargate_pod_execution_role_arn     = one(module.fargate_pod_execution_role[*].eks_fargate_pod_execution_role_arn)

  attributes = ["ebs-csi"]
  context    = module.this.context
}

# `aws-efs-csi-driver` EKS addon
# https://docs.aws.amazon.com/eks/latest/userguide/efs-csi.html
# https://github.com/kubernetes-sigs/aws-efs-csi-driver
resource "aws_iam_role_policy_attachment" "aws_efs_csi_driver" {
  count = local.efs_csi_sa_needed ? 1 : 0

  role       = module.aws_efs_csi_driver_eks_iam_role.service_account_role_name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEFSCSIDriverPolicy"
}

module "aws_efs_csi_driver_eks_iam_role" {
  source = "github.com/cloudposse/terraform-aws-eks-iam-role?ref=2.1.1"

  enabled = local.efs_csi_sa_needed

  eks_cluster_oidc_issuer_url = local.eks_cluster_oidc_issuer_url

  service_account_namespace_name_list = [
    "kube-system:efs-csi-controller-sa",
    "kube-system:efs-csi-node-sa",
  ]

  context = module.this.context
}


# This is split off into a separate file in the hopes we can drop it altogether in the future,
# or else move it into `roles-to-principals`.

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


#
# ONLY EDIT THIS FILE IN github.com/cloudposse/terraform-null-label
# All other instances of this file should be a copy of that one
#
#
# Copy this file from https://github.com/cloudposse/terraform-null-label/blob/master/exports/context.tf
# and then place it in your Terraform module to automatically get
# Cloud Posse's standard configuration inputs suitable for passing
# to Cloud Posse modules.
#
# curl -sL https://raw.githubusercontent.com/cloudposse/terraform-null-label/master/exports/context.tf -o context.tf
#
# Modules should access the whole context as `module.this.context`
# to get the input variables with nulls for defaults,
# for example `context = module.this.context`,
# and access individual variables as `module.this.<var>`,
# with final values filled in.
#
# For example, when using defaults, `module.this.context.delimiter`
# will be null, and `module.this.delimiter` will be `-` (hyphen).
#

module "this" {
  source = "github.com/cloudposse/terraform-null-label?ref=0.25.0"

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

# Copy contents of cloudposse/terraform-null-label/variables.tf here

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
    # Note: we have to use [] instead of null for unset lists due to
    # https://github.com/hashicorp/terraform/issues/28137
    # which was not fixed until Terraform 1.0.0,
    # but we want the default to be all the labels in `label_order`
    # and we want users to be able to prevent all tag generation
    # by setting `labels_as_tags` to `[]`, so we need
    # a different sentinel to indicate "default"
    labels_as_tags = ["unset"]
  }
  description = <<-EOT
    Single object for setting entire context at once.
    See description of individual variables for details.
    Leave string and numeric variables as `null` to use default value.
    Individual variable settings (non-null) override settings in context object,
    except for attributes, tags, and additional_tag_map, which are merged.
  EOT

  validation {
    condition     = lookup(var.context, "label_key_case", null) == null ? true : contains(["lower", "title", "upper"], var.context["label_key_case"])
    error_message = "Allowed values: `lower`, `title`, `upper`."
  }

  validation {
    condition     = lookup(var.context, "label_value_case", null) == null ? true : contains(["lower", "title", "upper", "none"], var.context["label_value_case"])
    error_message = "Allowed values: `lower`, `title`, `upper`, `none`."
  }
}

variable "enabled" {
  type        = bool
  default     = null
  description = "Set to false to prevent the module from creating any resources"
}

variable "namespace" {
  type        = string
  default     = null
  description = "ID element. Usually an abbreviation of your organization name, e.g. 'eg' or 'cp', to help ensure generated IDs are globally unique"
}

variable "tenant" {
  type        = string
  default     = null
  description = "ID element _(Rarely used, not included by default)_. A customer identifier, indicating who this instance of a resource is for"
}

variable "environment" {
  type        = string
  default     = null
  description = "ID element. Usually used for region e.g. 'uw2', 'us-west-2', OR role 'prod', 'staging', 'dev', 'UAT'"
}

variable "stage" {
  type        = string
  default     = null
  description = "ID element. Usually used to indicate role, e.g. 'prod', 'staging', 'source', 'build', 'test', 'deploy', 'release'"
}

variable "name" {
  type        = string
  default     = null
  description = <<-EOT
    ID element. Usually the component or solution name, e.g. 'app' or 'jenkins'.
    This is the only ID element not also included as a `tag`.
    The "name" tag is set to the full `id` string. There is no tag with the value of the `name` input.
    EOT
}

variable "delimiter" {
  type        = string
  default     = null
  description = <<-EOT
    Delimiter to be used between ID elements.
    Defaults to `-` (hyphen). Set to `""` to use no delimiter at all.
  EOT
}

variable "attributes" {
  type        = list(string)
  default     = []
  description = <<-EOT
    ID element. Additional attributes (e.g. `workers` or `cluster`) to add to `id`,
    in the order they appear in the list. New attributes are appended to the
    end of the list. The elements of the list are joined by the `delimiter`
    and treated as a single ID element.
    EOT
}

variable "labels_as_tags" {
  type        = set(string)
  default     = ["default"]
  description = <<-EOT
    Set of labels (ID elements) to include as tags in the `tags` output.
    Default is to include all labels.
    Tags with empty values will not be included in the `tags` output.
    Set to `[]` to suppress all generated tags.
    **Notes:**
      The value of the `name` tag, if included, will be the `id`, not the `name`.
      Unlike other `null-label` inputs, the initial setting of `labels_as_tags` cannot be
      changed in later chained modules. Attempts to change it will be silently ignored.
    EOT
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = <<-EOT
    Additional tags (e.g. `{'BusinessUnit': 'XYZ'}`).
    Neither the tag keys nor the tag values will be modified by this module.
    EOT
}

variable "additional_tag_map" {
  type        = map(string)
  default     = {}
  description = <<-EOT
    Additional key-value pairs to add to each map in `tags_as_list_of_maps`. Not added to `tags` or `id`.
    This is for some rare cases where resources want additional configuration of tags
    and therefore take a list of maps with tag key, value, and additional configuration.
    EOT
}

variable "label_order" {
  type        = list(string)
  default     = null
  description = <<-EOT
    The order in which the labels (ID elements) appear in the `id`.
    Defaults to ["namespace", "environment", "stage", "name", "attributes"].
    You can omit any of the 6 labels ("tenant" is the 6th), but at least one must be present.
    EOT
}

variable "regex_replace_chars" {
  type        = string
  default     = null
  description = <<-EOT
    Terraform regular expression (regex) string.
    Characters matching the regex will be removed from the ID elements.
    If not set, `"/[^a-zA-Z0-9-]/"` is used to remove all characters other than hyphens, letters and digits.
  EOT
}

variable "id_length_limit" {
  type        = number
  default     = null
  description = <<-EOT
    Limit `id` to this many characters (minimum 6).
    Set to `0` for unlimited length.
    Set to `null` for keep the existing setting, which defaults to `0`.
    Does not affect `id_full`.
    EOT
  validation {
    condition     = var.id_length_limit == null ? true : var.id_length_limit >= 6 || var.id_length_limit == 0
    error_message = "The id_length_limit must be >= 6 if supplied (not null), or 0 for unlimited length."
  }
}

variable "label_key_case" {
  type        = string
  default     = null
  description = <<-EOT
    Controls the letter case of the `tags` keys (label names) for tags generated by this module.
    Does not affect keys of tags passed in via the `tags` input.
    Possible values: `lower`, `title`, `upper`.
    Default value: `title`.
  EOT

  validation {
    condition     = var.label_key_case == null ? true : contains(["lower", "title", "upper"], var.label_key_case)
    error_message = "Allowed values: `lower`, `title`, `upper`."
  }
}

variable "label_value_case" {
  type        = string
  default     = null
  description = <<-EOT
    Controls the letter case of ID elements (labels) as included in `id`,
    set as tag values, and output by this module individually.
    Does not affect values of tags passed in via the `tags` input.
    Possible values: `lower`, `title`, `upper` and `none` (no transformation).
    Set this to `title` and set `delimiter` to `""` to yield Pascal Case IDs.
    Default value: `lower`.
    EOT

  validation {
    condition     = var.label_value_case == null ? true : contains(["lower", "title", "upper", "none"], var.label_value_case)
    error_message = "Allowed values: `lower`, `title`, `upper`, `none`."
  }
}

variable "descriptor_formats" {
  type        = any
  default     = {}
  description = <<-EOT
    Describe additional descriptors to be output in the `descriptors` output map.
    Map of maps. Keys are names of descriptors. Values are maps of the form
    `{
       format = string
       labels = list(string)
    }`
    (Type is `any` so the map values can later be enhanced to provide additional options.)
    `format` is a Terraform format string to be passed to the `format()` function.
    `labels` is a list of labels, in order, to pass to `format()` function.
    Label values will be normalized before being passed to `format()` so they will be
    identical to how they appear in `id`.
    Default is `{}` (`descriptors` output will be empty).
    EOT
}

#### End of copy of cloudposse/terraform-null-label/variables.tf


locals {
  node_groups_enabled = local.enabled && var.managed_node_groups_enabled

  node_group_default_availability_zones = var.node_group_defaults.availability_zones == null ? local.availability_zones : var.node_group_defaults.availability_zones
  node_group_default_kubernetes_version = var.node_group_defaults.kubernetes_version == null ? var.cluster_kubernetes_version : var.node_group_defaults.kubernetes_version

  # values(module.region_node_group) is an array of `region_node_group` objects
  # values(module.region_node_group)[*].region_node_groups is an array of
  #   maps with keys availability zones and values the output map of terraform-aws-eks-node-group
  # node_groups is a flattened array of output maps of terraform-aws-eks-node-group
  node_groups = flatten([for m in values(module.region_node_group)[*].region_node_groups : values(m)])

  # node_group_arns is a list of all the node group ARNs in the cluster
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

## Warn if you are using camelCase in the `block_device_map` argument.
## Without this warning, camelCase inputs will be silently ignored and replaced with defaults,
## which is very hard to notice and debug.
#
## We just need some kind of data source or resource to trigger the warning.
## Because we need it to run for each node group, there are no good options
## among actually useful data sources or resources. We also have to ensure
## that Terraform updates it when the `block_device_map` argument changes,
## and does not skip the checks because it can use the cached value.
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

# DEPRECATION SUPPORT
# `disk_size` and `disk_encryption_enabled are deprecated in favor of `block_device_map`.
# Convert legacy use to new format.

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
        } # ebs
      }   # "/dev/xvda"
    }     # k => { "/dev/xvda" = { ... } }
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

  source = "github.com/cloudposse/terraform-aws-eks-fargate-profile?ref=1.3.0"

  subnet_ids           = local.private_subnet_ids
  cluster_name         = local.eks_cluster_id
  permissions_boundary = var.fargate_profile_iam_role_permissions_boundary

  fargate_profile_enabled            = false
  fargate_pod_execution_role_enabled = true
  fargate_pod_execution_role_name    = local.fargate_cluster_pod_execution_role_name

  context = module.this.context
}


###############################################################################
### Both New and Legacy behavior, use caution when modifying
###############################################################################
module "fargate_profile" {
  source = "github.com/cloudposse/terraform-aws-eks-fargate-profile?ref=1.3.0"

  for_each = local.fargate_profiles

  subnet_ids                              = local.private_subnet_ids
  cluster_name                            = local.eks_cluster_id
  kubernetes_namespace                    = each.value.kubernetes_namespace
  kubernetes_labels                       = each.value.kubernetes_labels
  permissions_boundary                    = var.fargate_profile_iam_role_permissions_boundary
  iam_role_kubernetes_namespace_delimiter = var.fargate_profile_iam_role_kubernetes_namespace_delimiter

  ## Legacy switch
  fargate_pod_execution_role_enabled = var.legacy_fargate_1_role_per_profile_enabled
  fargate_pod_execution_role_arn     = var.legacy_fargate_1_role_per_profile_enabled ? null : one(module.fargate_pod_execution_role[*].eks_fargate_pod_execution_role_arn)

  context = module.this.context
}


# IAM Role for EC2 instance profile that is assigned to EKS worker nodes launched by Karpenter

# https://aws.amazon.com/blogs/aws/introducing-karpenter-an-open-source-high-performance-kubernetes-cluster-autoscaler/
# https://karpenter.sh/
# https://karpenter.sh/v0.10.1/getting-started/getting-started-with-terraform/
# https://karpenter.sh/v0.10.1/getting-started/getting-started-with-eksctl/
# https://www.eksworkshop.com/beginner/085_scaling_karpenter/
# https://karpenter.sh/v0.10.1/aws/provisioning/
# https://www.eksworkshop.com/beginner/085_scaling_karpenter/setup_the_environment/
# https://ec2spotworkshops.com/karpenter.html
# https://catalog.us-east-1.prod.workshops.aws/workshops/76a5dd80-3249-4101-8726-9be3eeee09b2/en-US/autoscaling/karpenter

locals {
  karpenter_iam_role_enabled = local.enabled && var.karpenter_iam_role_enabled

  karpenter_instance_profile_enabled = local.karpenter_iam_role_enabled && !var.legacy_do_not_create_karpenter_instance_profile

  # Used to determine correct partition (i.e. - `aws`, `aws-gov`, `aws-cn`, etc.)
  partition = one(data.aws_partition.current[*].partition)
}

data "aws_partition" "current" {
  count = local.karpenter_iam_role_enabled ? 1 : 0
}

module "karpenter_label" {
  source = "github.com/cloudposse/terraform-null-label?ref=0.25.0"

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

# IAM Role for EC2 instance profile that is assigned to EKS worker nodes launched by Karpenter
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

# AmazonSSMManagedInstanceCore policy is required by Karpenter
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

# Create a CNI policy that is a merger of AmazonEKS_CNI_Policy and required IPv6 permissions
# https://github.com/SummitRoute/aws_managed_policies/blob/master/policies/AmazonEKS_CNI_Policy
# https://docs.aws.amazon.com/eks/latest/userguide/cni-iam-role.html#cni-iam-role-create-ipv6-policy
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

  ## For future reference, as we enhance support for EKS Policies
  ## and namespace limits, here are some examples of entries:
  #  access_entry_map = {
  #    "arn:aws:iam::<acct>:role/prefix-admin" = {
  #      access_policy_associations = {
  #        ClusterAdmin = {}
  #      }
  #    }
  #    "arn:aws:iam::<account>:role/prefix-observer" = {
  #      kubernetes_groups = ["view"]
  #    }
  #  }
  #
  #  access_entry_map = merge({ for role in local.aws_team_roles_auth : role.rolearn => {
  #    kubernetes_groups          = role.groups
  #  } }, {for role in module.eks_workers[*].workers_role_arn : role => {
  #    type = "EC2_LINUX"
  #  }})

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

  # If Karpenter IAM role is enabled, give it access to the cluster to allow the nodes launched by Karpenter to join the EKS cluster
  karpenter_role_arn = one(aws_iam_role.karpenter[*].arn)

  linux_worker_role_arns = local.enabled ? concat(
    var.map_additional_worker_roles,
    # As of Karpenter v0.35.0, there is no entry in the official Karpenter documentation
    # stating how to configure Karpenter node roles via EKS Access Entries.
    # However, it is launching unmanaged worker nodes, so it makes sense that they
    # be configured as EC2_LINUX unmanaged worker nodes. Of course, this probably
    # does not work if they are Windows nodes, but at the moment, this component
    # probably has other deficiencies that would prevent it from working with Windows nodes,
    # so we will stick with just saying Windows is not supported until we have some need for it.
    local.karpenter_iam_role_enabled ? [local.karpenter_role_arn] : [],
  ) : []

  # For backwards compatibility, we need to add the unmanaged worker role ARNs, but
  # historically we did not care whether they were LINUX or WINDOWS.
  # Best we can do is guess that they are LINUX. The `eks-cluster` module
  # did not give them all the support needed to run Windows anyway.
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

  # Create a map of AZ IDs to AZ names (and the reverse),
  # but fail safely, because AZ IDs are not always available.
  az_id_map = length(local.availability_zone_ids_expanded) > 0 ? try(zipmap(data.aws_availability_zones.default[0].zone_ids, data.aws_availability_zones.default[0].names), {}) : {}

  availability_zones_normalized = length(local.availability_zone_ids_expanded) > 0 ? [
    for v in local.availability_zone_ids_expanded : local.az_id_map[v]
  ] : local.availability_zones_expanded

  # Get only the public subnets that correspond to the AZs provided in `var.availability_zones`
  # `az_public_subnets_map` is a map of AZ names to list of public subnet IDs in the AZs
  # LEGACY SUPPORT for legacy VPC with no az_public_subnets_map
  public_subnet_ids = try(flatten([
    for k, v in local.vpc_outputs.az_public_subnets_map : v
    if contains(var.availability_zones, k) || length(var.availability_zones) == 0
    ]),
  local.vpc_outputs.public_subnet_ids)

  # Get only the private subnets that correspond to the AZs provided in `var.availability_zones`
  # `az_private_subnets_map` is a map of AZ names to list of private subnet IDs in the AZs
  # LEGACY SUPPORT for legacy VPC with no az_public_subnets_map
  private_subnet_ids = try(flatten([
    for k, v in local.vpc_outputs.az_private_subnets_map : v
    if contains(var.availability_zones, k) || length(var.availability_zones) == 0
    ]),
  local.vpc_outputs.private_subnet_ids)

  # Infer the availability zones from the private subnets if var.availability_zones is empty:
  availability_zones = local.enabled ? (length(local.availability_zones_normalized) == 0 ? keys(local.vpc_outputs.az_private_subnets_map) : local.availability_zones_normalized) : []
}

data "aws_availability_zones" "default" {
  count = length(local.availability_zone_ids_expanded) > 0 ? 1 : 0

  # Filter out Local Zones. See https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/availability_zones#by-filter
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }

  # Pin zone identity to prevent silent expansion when AWS adds an Availability Zone
  zone_ids = local.availability_zone_ids_expanded

  lifecycle {
    postcondition {
      condition     = length(self.zone_ids) > 0
      error_message = "No availability zones IDs found in region ${var.region}. You must specify availability zones instead."
    }
  }
}

module "utils" {
  source = "github.com/cloudposse/terraform-aws-utils?ref=1.3.0"
}

module "eks_cluster" {
  source = "github.com/cloudposse/terraform-aws-eks-cluster?ref=4.1.0"

  region     = var.region
  attributes = local.attributes

  access_config            = var.access_config
  access_entry_map         = local.access_entry_map
  access_entries_for_nodes = local.access_entries_for_nodes


  allowed_security_group_ids   = var.allowed_security_groups
  allowed_cidr_blocks          = local.allowed_cidr_blocks
  cluster_log_retention_period = var.cluster_log_retention_period
  enabled_cluster_log_types    = length(var.enabled_cluster_log_types) > 0 ? var.enabled_cluster_log_types : ["api", "audit", "authenticator", "controllerManager", "scheduler"]
  endpoint_private_access      = var.cluster_endpoint_private_access
  endpoint_public_access       = false
  kubernetes_version           = var.cluster_kubernetes_version
  oidc_provider_enabled        = var.oidc_provider_enabled
  public_access_cidrs          = []
  subnet_ids                   = var.cluster_private_subnets_only ? local.private_subnet_ids : concat(local.private_subnet_ids, local.public_subnet_ids)


  # EKS addons
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
  description = "The name of the cluster"
  value       = module.eks_cluster.eks_cluster_id
}

output "eks_cluster_arn" {
  description = "The Amazon Resource Name (ARN) of the cluster"
  value       = module.eks_cluster.eks_cluster_arn
}

output "eks_cluster_endpoint" {
  description = "The endpoint for the Kubernetes API server"
  value       = module.eks_cluster.eks_cluster_endpoint
}

output "eks_cluster_identity_oidc_issuer" {
  description = "The OIDC Identity issuer for the cluster"
  value       = module.eks_cluster.eks_cluster_identity_oidc_issuer
}

output "eks_cluster_certificate_authority_data" {
  description = "The Kubernetes cluster certificate authority data"
  value       = module.eks_cluster.eks_cluster_certificate_authority_data
}

output "eks_cluster_managed_security_group_id" {
  description = "Security Group ID that was created by EKS for the cluster. EKS creates a Security Group and applies it to ENI that is attached to EKS Control Plane master nodes and to any managed workloads"
  value       = module.eks_cluster.eks_cluster_managed_security_group_id
}

output "eks_cluster_version" {
  description = "The Kubernetes server version of the cluster"
  value       = module.eks_cluster.eks_cluster_version
}

output "eks_node_group_arns" {
  description = "List of all the node group ARNs in the cluster"
  value       = local.node_group_arns
}

output "eks_managed_node_workers_role_arns" {
  description = "List of ARNs for workers in managed node groups"
  value       = local.node_group_role_arns
}

output "eks_node_group_count" {
  description = "Count of the worker nodes"
  value       = length(local.node_group_arns)
}

output "eks_node_group_ids" {
  description = "EKS Cluster name and EKS Node Group name separated by a colon"
  value       = compact([for group in local.node_groups : group.eks_node_group_id])
}

output "eks_node_group_role_names" {
  description = "List of worker nodes IAM role names"
  value       = compact(flatten([for group in local.node_groups : group.eks_node_group_role_name]))
}

output "eks_auth_worker_roles" {
  description = "List of worker IAM roles that were included in the `auth-map` ConfigMap."
  value       = local.linux_worker_role_arns
}

output "eks_node_group_statuses" {
  description = "Status of the EKS Node Group"
  value       = compact([for group in local.node_groups : group.eks_node_group_status])
}

output "karpenter_iam_role_arn" {
  description = "Karpenter IAM Role ARN"
  value       = one(aws_iam_role.karpenter[*].arn)
}

output "karpenter_iam_role_name" {
  description = "Karpenter IAM Role name"
  value       = one(aws_iam_role.karpenter[*].name)
}

output "fargate_profiles" {
  description = "Fargate Profiles"
  value       = merge(module.fargate_profile, local.addon_fargate_profiles)
}

output "fargate_profile_role_arns" {
  description = "Fargate Profile Role ARNs"
  value = distinct(compact(concat(values(module.fargate_profile)[*].eks_fargate_profile_role_arn,
    [one(module.fargate_pod_execution_role[*].eks_fargate_pod_execution_role_arn)]
  )))

}

output "fargate_profile_role_names" {
  description = "Fargate Profile Role names"
  value = distinct(compact(concat(values(module.fargate_profile)[*].eks_fargate_profile_role_name,
    [one(module.fargate_pod_execution_role[*].eks_fargate_pod_execution_role_name)]
  )))
}

output "vpc_cidr" {
  description = "The CIDR of the VPC where this cluster is deployed."
  value       = local.vpc_outputs.vpc_cidr
}

output "availability_zones" {
  description = "Availability Zones in which the cluster is provisioned"
  value       = local.availability_zones
}

output "eks_addons_versions" {
  description = "Map of enabled EKS Addons names and versions"
  value       = module.eks_cluster.eks_addons_versions
}


provider "aws" {
  region = var.region

  assume_role {
    # WARNING:
    #   The EKS cluster is owned by the role that created it, and that
    #   role is the only role that can access the cluster without an
    #   entry in the auth-map ConfigMap, so it is crucial it is created
    #   with the provisioned Terraform role and not an SSO role that could
    #   be removed without notice.
    #
    # This should only be run using the target account's Terraform role.
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
  source = "github.com/cloudposse/terraform-yaml-stack-config//modules/remote-state?ref=1.5.0"

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
  source = "github.com/cloudposse/terraform-yaml-stack-config//modules/remote-state?ref=1.5.0"

  for_each = local.accounts_with_vpc

  component   = var.vpc_component_name
  environment = try(each.value.environment, module.this.environment)
  stage       = try(each.value.stage, module.this.stage)
  tenant      = try(each.value.tenant, module.this.tenant)

  context = module.this.context
}



variable "apply_config_map_aws_auth" {
  type        = bool
  description = <<-EOT
    (Obsolete) Whether to execute `kubectl apply` to apply the ConfigMap to allow worker nodes to join the EKS cluster.
    This input is included to avoid breaking existing configurations that set it to `true`;
    a value of `false` is no longer allowed.
    This input is obsolete and will be removed in a future release.
    EOT
  default     = true
  nullable    = false
  validation {
    condition     = var.apply_config_map_aws_auth == true
    error_message = <<-EOT
      This component no longer supports the `aws-auth` ConfigMap and always updates the access.
      This input is obsolete and will be removed in a future release.
      EOT
  }
}

variable "map_additional_aws_accounts" {
  type        = list(string)
  description = <<-EOT
    (Obsolete) Additional AWS accounts to grant access to the EKS cluster.
    This input is included to avoid breaking existing configurations that
    supplied an empty list, but the list is no longer allowed to have entries.
    (It is not clear that it worked properly in earlier versions in any case.)
    This component now only supports EKS access entries, which require full principal ARNs.
    This input is deprecated and will be removed in a future release.
    EOT
  default     = []
  nullable    = false
  validation {
    condition     = length(var.map_additional_aws_accounts) == 0
    error_message = <<-EOT
      This component no longer supports `map_additional_aws_accounts`.
      (It is not clear that it worked properly in earlier versions in any case.)
      This component only supports EKS access entries, which require full principal ARNs.
      This input is deprecated and will be removed in a future release.
      EOT
  }
}

variable "map_additional_worker_roles" {
  type        = list(string)
  description = <<-EOT
    (Deprecated) AWS IAM Role ARNs of unmanaged Linux worker nodes to grant access to the EKS cluster.
    In earlier versions, this could be used to grant access to worker nodes of any type
    that were not managed by the EKS cluster. Now EKS requires that unmanaged worker nodes
    be classified as Linux or Windows servers, in this input is temporarily retained
    with the assumption that all worker nodes are Linux servers. (It is likely that
    earlier versions did not work properly with Windows worker nodes anyway.)
    This input is deprecated and will be removed in a future release.
    In the future, this component will either have a way to separate Linux and Windows worker nodes,
    or drop support for unmanaged worker nodes entirely.
    EOT
  default     = []
  nullable    = false
}


variable "region" {
  type        = string
  description = "AWS Region"
}

variable "availability_zones" {
  type        = list(string)
  description = <<-EOT
    AWS Availability Zones in which to deploy multi-AZ resources.
    Ignored if `availability_zone_ids` is set.
    Can be the full name, e.g. `us-east-1a`, or just the part after the region, e.g. `a` to allow reusable values across regions.
    If not provided, resources will be provisioned in every zone with a private subnet in the VPC.
    EOT
  default     = []
  nullable    = false
}

variable "availability_zone_ids" {
  type        = list(string)
  description = <<-EOT
    List of Availability Zones IDs where subnets will be created. Overrides `availability_zones`.
    Can be the full name, e.g. `use1-az1`, or just the part after the AZ ID region code, e.g. `-az1`,
    to allow reusable values across regions. Consider contention for resources and spot pricing in each AZ when selecting.
    Useful in some regions when using only some AZs and you want to use the same ones across multiple accounts.
    EOT
  default     = []
}

variable "availability_zone_abbreviation_type" {
  type        = string
  description = "Type of Availability Zone abbreviation (either `fixed` or `short`) to use in names. See https://github.com/cloudposse/terraform-aws-utils for details."
  default     = "fixed"
  nullable    = false

  validation {
    condition     = contains(["fixed", "short"], var.availability_zone_abbreviation_type)
    error_message = "The availability_zone_abbreviation_type must be either \"fixed\" or \"short\"."
  }
}

variable "managed_node_groups_enabled" {
  type        = bool
  description = "Set false to prevent the creation of EKS managed node groups."
  default     = true
  nullable    = false
}

variable "oidc_provider_enabled" {
  type        = bool
  description = "Create an IAM OIDC identity provider for the cluster, then you can create IAM roles to associate with a service account in the cluster, instead of using kiam or kube2iam. For more information, see https://docs.aws.amazon.com/eks/latest/userguide/enable-iam-roles-for-service-accounts.html"
  default     = true
  nullable    = false
}

variable "cluster_endpoint_private_access" {
  type        = bool
  description = "Indicates whether or not the Amazon EKS private API server endpoint is enabled. Default to AWS EKS resource and it is `false`"
  default     = false
  nullable    = false
}

variable "cluster_endpoint_public_access" {
  type        = bool
  description = "Indicates whether or not the Amazon EKS public API server endpoint is enabled. Default to AWS EKS resource and it is `true`"
  default     = true
  nullable    = false
}

variable "cluster_kubernetes_version" {
  type        = string
  description = "Desired Kubernetes master version. If you do not specify a value, the latest available version is used"
  default     = null
}

variable "public_access_cidrs" {
  type        = list(string)
  description = "Indicates which CIDR blocks can access the Amazon EKS public API server endpoint when enabled. EKS defaults this to a list with 0.0.0.0/0."
  default     = ["0.0.0.0/0"]
  nullable    = false
}

variable "enabled_cluster_log_types" {
  type        = list(string)
  description = "A list of the desired control plane logging to enable. For more information, see https://docs.aws.amazon.com/en_us/eks/latest/userguide/control-plane-logs.html. Possible values [`api`, `audit`, `authenticator`, `controllerManager`, `scheduler`]"
  default     = []
  nullable    = false
}

variable "cluster_log_retention_period" {
  type        = number
  description = "Number of days to retain cluster logs. Requires `enabled_cluster_log_types` to be set. See https://docs.aws.amazon.com/en_us/eks/latest/userguide/control-plane-logs.html."
  default     = 0
  nullable    = false
}

# TODO:
# - Support EKS Access Policies
# - Support namespaced access limits
# - Support roles from other accounts
# - Either combine with Permission Sets or similarly enhance Permission Set support
variable "aws_team_roles_rbac" {
  type = list(object({
    aws_team_role = string
    groups        = list(string)
  }))

  description = "List of `aws-team-roles` (in the target AWS account) to map to Kubernetes RBAC groups."
  default     = []
  nullable    = false
}

variable "aws_sso_permission_sets_rbac" {
  type = list(object({
    aws_sso_permission_set = string
    groups                 = list(string)
  }))

  description = <<-EOT
    (Not Recommended): AWS SSO (IAM Identity Center) permission sets in the EKS deployment account to add to `aws-auth` ConfigMap.
    Unfortunately, `aws-auth` ConfigMap does not support SSO permission sets, so we map the generated
    IAM Role ARN corresponding to the permission set at the time Terraform runs. This is subject to change
    when any changes are made to the AWS SSO configuration, invalidating the mapping, and requiring a
    `terraform apply` in this project to update the `aws-auth` ConfigMap and restore access.
    EOT

  default  = []
  nullable = false
}

# TODO:
# - Support EKS Access Policies
# - Support namespaced access limits
# - Combine with`map_additional_iam_users` into new input
variable "map_additional_iam_roles" {
  type = list(object({
    rolearn  = string
    username = optional(string)
    groups   = list(string)
  }))

  description = <<-EOT
    Additional IAM roles to grant access to the cluster.
    *WARNING*: Full Role ARN, including path, is required for `rolearn`.
    In earlier versions (with `aws-auth` ConfigMap), only the path
    had to be removed from the Role ARN. The path is now required.
    `username` is now ignored. This input is planned to be replaced
    in a future release with a more flexible input structure that consolidates
    `map_additional_iam_roles` and `map_additional_iam_users`.
    EOT
  default     = []
  nullable    = false
}

variable "map_additional_iam_users" {
  type = list(object({
    userarn  = string
    username = optional(string)
    groups   = list(string)
  }))

  description = <<-EOT
    Additional IAM roles to grant access to the cluster.
    `username` is now ignored. This input is planned to be replaced
    in a future release with a more flexible input structure that consolidates
    `map_additional_iam_roles` and `map_additional_iam_users`.
    EOT
  default     = []
  nullable    = false
}

variable "allowed_security_groups" {
  type        = list(string)
  description = "List of Security Group IDs to be allowed to connect to the EKS cluster"
  default     = []
  nullable    = false
}

variable "allowed_cidr_blocks" {
  type        = list(string)
  description = "List of CIDR blocks to be allowed to connect to the EKS cluster"
  default     = []
  nullable    = false
}

variable "subnet_type_tag_key" {
  type        = string
  description = "The tag used to find the private subnets to find by availability zone. If null, will be looked up in vpc outputs."
  default     = null
}

variable "color" {
  type        = string
  description = "The cluster stage represented by a color; e.g. blue, green"
  default     = ""
  nullable    = false
}

variable "node_groups" {
  # will create 1 node group for each item in map
  type = map(object({
    # EKS AMI version to use, e.g. "1.16.13-20200821" (no "v").
    ami_release_version = optional(string, null)
    # Type of Amazon Machine Image (AMI) associated with the EKS Node Group
    ami_type = optional(string, null)
    # Additional attributes (e.g. `1`) for the node group
    attributes = optional(list(string), null)
    # will create 1 auto scaling group in each specified availability zone
    # or all AZs with subnets if none are specified anywhere
    availability_zones = optional(list(string), null)
    # Whether to enable Node Group to scale its AutoScaling Group
    cluster_autoscaler_enabled = optional(bool, null)
    # True to create new node_groups before deleting old ones, avoiding a temporary outage
    create_before_destroy = optional(bool, null)
    # Desired number of worker nodes when initially provisioned
    desired_group_size = optional(number, null)
    # Set of instance types associated with the EKS Node Group. Terraform will only perform drift detection if a configuration value is provided.
    instance_types = optional(list(string), null)
    # Key-value mapping of Kubernetes labels. Only labels that are applied with the EKS API are managed by this argument. Other Kubernetes labels applied to the EKS Node Group will not be managed
    kubernetes_labels = optional(map(string), null)
    # List of objects describing Kubernetes taints.
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
    # Desired Kubernetes master version. If you do not specify a value, the latest available version is used
    kubernetes_version = optional(string, null)
    # The maximum size of the AutoScaling Group
    max_group_size = optional(number, null)
    # The minimum size of the AutoScaling Group
    min_group_size = optional(number, null)
    # List of auto-launched resource types to tag
    resources_to_tag = optional(list(string), null)
    tags             = optional(map(string), null)

    # block_device_map copied from cloudposse/terraform-aws-eks-node-group
    # Keep in sync via copy and paste, but make optional.
    # Most of the time you want "/dev/xvda". For BottleRocket, use "/dev/xvdb".
    block_device_map = optional(map(object({
      no_device    = optional(bool, null)
      virtual_name = optional(string, null)
      ebs = optional(object({
        delete_on_termination = optional(bool, true)
        encrypted             = optional(bool, true)
        iops                  = optional(number, null)
        kms_key_id            = optional(string, null)
        snapshot_id           = optional(string, null)
        throughput            = optional(number, null) # for gp3, MiB/s, up to 1000
        volume_size           = optional(number, 20)   # Disk size in GB
        volume_type           = optional(string, "gp3")

        # Catch common camel case typos. These have no effect, they just generate better errors.
        # It would be nice to actually use these, but volumeSize in particular is a number here
        # and in most places it is a string with a unit suffix (e.g. 20Gi)
        # Without these defined, they would be silently ignored and the default values would be used instead,
        # which is difficult to debug.
        deleteOnTermination = optional(any, null)
        kmsKeyId            = optional(any, null)
        snapshotId          = optional(any, null)
        volumeSize          = optional(any, null)
        volumeType          = optional(any, null)
      }))
    })), null)

    # DEPRECATED:
    # Enable disk encryption for the created launch template (if we aren't provided with an existing launch template)
    # DEPRECATED: disk_encryption_enabled is DEPRECATED, use `block_device_map` instead.
    disk_encryption_enabled = optional(bool, null)
    # Disk size in GiB for worker nodes. Terraform will only perform drift detection if a configuration value is provided.
    # DEPRECATED: disk_size is DEPRECATED, use `block_device_map` instead.
    disk_size = optional(number, null)

  }))

  description = "List of objects defining a node group for the cluster"
  default     = {}
  nullable    = false
}

variable "node_group_defaults" {
  # Any value in the node group that is null will be replaced
  # by the value in this object, which can also be null
  type = object({
    ami_release_version        = optional(string, null)
    ami_type                   = optional(string, null)
    attributes                 = optional(list(string), null)
    availability_zones         = optional(list(string)) # set to null to use var.availability_zones
    cluster_autoscaler_enabled = optional(bool, null)
    create_before_destroy      = optional(bool, null)
    desired_group_size         = optional(number, null)
    instance_types             = optional(list(string), null)
    kubernetes_labels          = optional(map(string), {})
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
    kubernetes_version = optional(string, null) # set to null to use cluster_kubernetes_version
    max_group_size     = optional(number, null)
    min_group_size     = optional(number, null)
    resources_to_tag   = optional(list(string), null)
    tags               = optional(map(string