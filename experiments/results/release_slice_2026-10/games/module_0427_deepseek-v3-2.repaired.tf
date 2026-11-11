locals {
  # If you have custom policies, override this declaration by creating
  # a file called `additional-policy-map_override.tf`.
  # Then add the custom policies to the overridable_additional_custom_policy_map in that file.
  # See the README for more details.
  overridable_additional_custom_policy_map = {
    # Example:
    #   eks_viewer = aws_iam_policy.eks_viewer.arn
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
  source  = "cloudposse/label/null"
  version = "0.25.0"

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
  roles_config      = { for key, value in var.roles : key => value if lookup(value, "enabled", false) }
  roles_policy_arns = { for role, config in local.roles_config : role => config.role_policy_arns }

  # It would be nice if we could use null-label and set name = each.key but we do not want the name to be normalized
  role_name_map = { for role_name, config in local.roles_config : role_name => format("%s%s%s", module.this.id, module.this.delimiter, role_name) }

  role_name_role_arn_map = { for key, value in local.roles_config : key => try(aws_iam_role.default[key].arn, null) }

  # If you want to create custom policies to add to multiple roles by name, create the policy
  # using an aws_iam_policy resource and then map it to the name you want to use in the
  # YAML configuration by adding an entry in `custom_policy_map`.
  supplied_custom_policy_map = {
    eks_viewer  = try(aws_iam_policy.eks_viewer[0].arn, null)
    vpn_planner = try(aws_iam_policy.vpn_planner[0].arn, null)
    kms_planner = try(aws_iam_policy.kms_planner[0].arn, null)
  }
  custom_policy_map = merge(local.supplied_custom_policy_map, local.overridable_additional_custom_policy_map)

  configured_policies = flatten([for k, v in local.roles_config : v.role_policy_arns])

  # Intermediate step in calculating all policy attachments.
  # Create a list of [role, arn] lists
  # role_attachments_product_list = concat([ for role_name, config in var.roles_config : setproduct([role_name], [for arn in config.role_policy_arns : arn]) ]...)
  # Also work around https://github.com/hashicorp/terraform/issues/22404
  # Create a list of strings that combine role name with policy ARN to attach to the role
  role_attachments_product_list = flatten([for role_name, arns in local.roles_policy_arns : [for arn in arns : "${role_name}+${arn}"]])
  role_attachments = { for role_arns in local.role_attachments_product_list : (
    # Make the first key just the role name, to keep the keys short when possible
    local.roles_policy_arns[split("+", role_arns)[0]][0] == split("+", role_arns)[1] ? split("+", role_arns)[0] : role_arns) =>
    # The value is the policy ARN to attach to the role
    try(local.custom_policy_map[split("+", role_arns)[1]], split("+", role_arns)[1])
  }

  this_account_name             = try(module.this.account, module.this.descriptors["account_name"], module.this.stage)
  identity_account_account_name = module.iam_roles.identity_account_account_name

  aws_partition = module.iam_roles.aws_partition
}

module "assume_role" {
  for_each = local.roles_config
  source   = "../account-map/modules/team-assume-role-policy"

  allowed_roles           = { (local.identity_account_account_name) = each.value.trusted_teams }
  denied_roles            = { (local.identity_account_account_name) = each.value.denied_teams }
  allowed_principal_arns  = each.value.trusted_role_arns
  denied_principal_arns   = each.value.denied_role_arns
  allowed_permission_sets = { (local.this_account_name) = each.value.trusted_permission_sets }
  denied_permission_sets  = { (local.this_account_name) = each.value.denied_permission_sets }

  trusted_github_repos = try(var.trusted_github_repos[each.key], [])

  privileged = true

  context = module.this.context
}

data "aws_iam_policy_document" "assume_role_aggregated" {
  for_each = local.roles_config

  source_policy_documents = compact(concat([module.assume_role[each.key].policy_document,
    module.assume_role[each.key].github_assume_role_policy],
  local.roles_config[each.key].aws_saml_login_enabled ? [module.aws_saml.outputs.saml_provider_assume_role_policy] : []))
}

resource "aws_iam_role" "default" {
  for_each = local.roles_config

  name                 = local.role_name_map[each.key]
  description          = each.value["role_description"]
  assume_role_policy   = data.aws_iam_policy_document.assume_role_aggregated[each.key].json
  max_session_duration = each.value["max_session_duration"]
  tags                 = merge(module.this.tags, { Name = local.role_name_map[each.key] })
}

resource "aws_iam_role_policy_attachment" "default" {
  for_each = local.role_attachments

  role       = aws_iam_role.default[split("+", each.key)[0]].name
  policy_arn = each.value
}


output "role_name_role_arn_map" {
  description = "Map of role names to role ARNs"
  value       = local.role_name_role_arn_map
}

resource "local_file" "account_info" {
  content = templatefile("${path.module}/iam-role-info.tftmpl", {
    role_name_map          = local.role_name_map
    role_name_role_arn_map = local.role_name_role_arn_map
    namespace              = module.this.namespace
  })
  filename = "${path.module}/iam-role-info/${module.this.id}.sh"
}


locals {
  eks_viewer_enabled = contains(local.configured_policies, "eks_viewer")
}

data "aws_iam_policy_document" "eks_view_access" {
  count = local.eks_viewer_enabled ? 1 : 0

  statement {
    sid    = "AllowEKSView"
    effect = "Allow"
    actions = [
      "eks:Get*",
      "eks:Describe*",
      "eks:List*",
      "eks:Access*"
    ]
    resources = [
      "arn:${local.aws_partition}:eks:*:${data.aws_caller_identity.current.account_id}:cluster/*"
    ]
  }

}

data "aws_iam_policy_document" "eks_viewer_access_aggregated" {
  count = local.eks_viewer_enabled ? 1 : 0

  source_policy_documents = [
    data.aws_iam_policy_document.eks_view_access[0].json,
  ]
}

resource "aws_iam_policy" "eks_viewer" {
  count = local.eks_viewer_enabled ? 1 : 0

  name   = format("%s-eks_viewer", module.this.id)
  policy = data.aws_iam_policy_document.eks_viewer_access_aggregated[0].json

  tags = module.this.tags
}


locals {
  kms_planner_enabled = contains(local.configured_policies, "kms_planner")
}

data "aws_iam_policy_document" "kms_planner_access" {
  count = local.kms_planner_enabled ? 1 : 0

  statement {
    sid    = "AllowKMSDecrypt"
    effect = "Allow"

    actions = [
      "kms:Decrypt",
    ]

    # Only allow decryption of SSM parameters.
    # To further restrict to specific parameters, add conditions on the value of 
    #   kms:EncryptionContext:PARAMETER_ARN
    # See https://docs.aws.amazon.com/kms/latest/developerguide/services-parameter-store.html#parameter-store-encryption-context
    condition {
      test     = "Null"
      variable = "kms:EncryptionContext:PARAMETER_ARN"
      values   = ["false"]
    }

    resources = [
      "arn:${local.aws_partition}:kms:*:${data.aws_caller_identity.current.account_id}:key/*"
    ]
  }

}

data "aws_iam_policy_document" "kms_planner_access_aggregated" {
  count = local.kms_planner_enabled ? 1 : 0

  source_policy_documents = [
    data.aws_iam_policy_document.kms_planner_access[0].json,
  ]
}

resource "aws_iam_policy" "kms_planner" {
  count = local.kms_planner_enabled ? 1 : 0

  name   = format("%s-kms_planner", module.this.id)
  policy = data.aws_iam_policy_document.kms_planner_access_aggregated[0].json

  tags = module.this.tags
}


locals {
  vpn_planner_enabled = contains(local.configured_policies, "vpn_planner")
}

data "aws_iam_policy_document" "vpn_planner_access" {
  count = local.vpn_planner_enabled ? 1 : 0

  statement {
    sid    = "AllowVPNReader"
    effect = "Allow"
    actions = [
      "ec2:ExportClientVpnClientConfiguration",
    ]
    resources = [
      "arn:${local.aws_partition}:ec2:*:${data.aws_caller_identity.current.account_id}:client-vpn-endpoint/*"
    ]
  }

}

data "aws_iam_policy_document" "vpn_planner_access_aggregated" {
  count = local.vpn_planner_enabled ? 1 : 0

  source_policy_documents = [
    data.aws_iam_policy_document.vpn_planner_access[0].json,
  ]
}

resource "aws_iam_policy" "vpn_planner" {
  count = local.vpn_planner_enabled ? 1 : 0

  name   = format("%s-vpn_planner", module.this.id)
  policy = data.aws_iam_policy_document.vpn_planner_access_aggregated[0].json

  tags = module.this.tags
}


provider "aws" {
  region = var.region

  # aws-team-roles, since it creates the initial "admin", "terraform", and other roles,
  # must be run as SuperAdmin, and cannot use "profile" instead of "role_arn"
  # even if the components are generally using profiles.
  # Note the role_arn is the ARN of the OrganizationAccountAccessRole, not the SAML role.

  dynamic "assume_role" {
    for_each = var.import_role_arn == null ? (module.iam_roles.org_role_arn != null ? [true] : []) : ["import"]
    content {
      role_arn = coalesce(var.import_role_arn, module.iam_roles.org_role_arn)
    }
  }
}

module "iam_roles" {
  source     = "../account-map/modules/iam-roles"
  privileged = true
  context    = module.this.context
}

variable "import_role_arn" {
  type        = string
  default     = null
  description = "IAM Role ARN to use when importing a resource"
}


module "aws_saml" {
  source  = "cloudposse/stack-config/yaml//modules/remote-state"
  version = "1.5.0"

  component  = "aws-saml"
  privileged = true

  ignore_errors = true

  defaults = {
    saml_provider_assume_role_policy = ""
  }

  context = module.this.context
}


variable "region" {
  type        = string
  description = "AWS Region"
}

variable "roles" {
  description = "A map of roles to configure the accounts."
  type = map(object({
    enabled = bool

    denied_teams            = list(string)
    denied_permission_sets  = list(string)
    denied_role_arns        = list(string)
    max_session_duration    = number # in seconds 3600 <= max <= 43200 (12 hours)
    role_description        = string
    role_policy_arns        = list(string)
    aws_saml_login_enabled  = bool
    trusted_teams           = list(string)
    trusted_permission_sets = list(string)
    trusted_role_arns       = list(string)
  }))
}

variable "trusted_github_repos" {
  type        = map(list(string))
  description = <<-EOT
    Map where keys are role names (same keys as `roles`) and values are lists of
    GitHub repositories allowed to assume those roles. See `account-map/modules/github-assume-role-policy.mixin.tf`
    for specifics about repository designations.
    EOT
  default     = {}
}

data "aws_caller_identity" "current" {}


terraform {
  required_version = ">= 1.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 4.9.0"
    }
    local = {
      source  = "hashicorp/local"
      version = ">= 1.3"
    }
  }
}