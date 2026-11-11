module "this" {
  source = "git::https://github.com/cloudposse/terraform-null-label.git?ref=0.25.0"

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
    labels_as_tags      = ["unset"]
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

locals {
  roles_config      = { for key, value in var.roles : key => value if lookup(value, "enabled", false) }
  roles_policy_arns = { for role, config in local.roles_config : role => config.role_policy_arns }

  role_name_map = { for role_name, config in local.roles_config : role_name => format("%s%s%s", module.this.id, module.this.delimiter, role_name) }

  custom_policy_map = {
    billing_read_only = try(aws_iam_policy.billing_read_only[0].arn, null)
    billing_admin     = try(aws_iam_policy.billing_admin[0].arn, null)
    support           = try(aws_iam_policy.support[0].arn, null)
  }

  configured_policies = flatten([for k, v in local.roles_config : v.role_policy_arns])

  role_attachments_product_list = flatten([for role_name, arns in local.roles_policy_arns : [for arn in arns : "${role_name}+${arn}"]])
  role_attachments = { for role_arns in local.role_attachments_product_list : (
    local.roles_policy_arns[split("+", role_arns)[0]][0] == split("+", role_arns)[1] ? split("+", role_arns)[0] : role_arns) =>
    try(local.custom_policy_map[split("+", role_arns)[1]], split("+", role_arns)[1])
  }

  saml_login_enabled = module.this.enabled && length(local.saml_provider_arns) > 0 ? contains([for v in local.roles_config : (v.enabled && v.sso_login_enabled)], true) : false
  saml_provider_arns = try(module.sso.outputs.saml_provider_arns, [])

  this_account_name = try(module.this.account, module.this.descriptors["account_name"], module.this.stage)

  aws_partition = data.aws_partition.current.partition
}

data "aws_partition" "current" {}

module "assume_role" {
  for_each = local.roles_config
  source   = "../../modules/account-map/modules/iam-assume-role-policy"

  allowed_roles           = { (var.iam_primary_roles_account_name) = each.value.trusted_primary_roles }
  denied_roles            = { (var.iam_primary_roles_account_name) = each.value.denied_primary_roles }
  allowed_principal_arns  = each.value.trusted_role_arns
  denied_principal_arns   = each.value.denied_role_arns
  allowed_permission_sets = { (local.this_account_name) = each.value.trusted_permission_sets }
  denied_permission_sets  = { (local.this_account_name) = each.value.denied_permission_sets }

  privileged = true

  context = module.this.context
}

data "aws_iam_policy_document" "saml_provider_assume" {
  count = local.saml_login_enabled ? 1 : 0

  statement {
    sid = "SamlProviderAssume"
    actions = [
      "sts:AssumeRoleWithSAML",
      "sts:TagSession",
    ]

    principals {
      type = "Federated"

      identifiers = [for name, arn in local.saml_provider_arns : arn]
    }

    condition {
      test     = "StringEquals"
      variable = "SAML:aud"
      values   = ["https://signin.aws.amazon.com/saml"]
    }
  }
}

data "aws_iam_policy_document" "assume_role_aggregated" {
  for_each = local.roles_config

  source_policy_documents = concat([module.assume_role[each.key].policy_document],
  local.saml_login_enabled && local.roles_config[each.key].sso_login_enabled ? [data.aws_iam_policy_document.saml_provider_assume[0].json] : [])
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
  value       = { for key, value in local.roles_config : key => try(aws_iam_role.default[key].arn, null) }
}

output "role_long_name_policy_arn_map" {
  description = "Map of role long names to attached IAM Policy ARNs"
  value       = { for key, value in local.roles_config : try(aws_iam_role.default[key].name, key) => try(aws_iam_role_policy_attachment.default[key].policy_arn, null) }
}

locals {
  billing_read_only_policy_enabled = contains(local.configured_policies, "billing_read_only")
  billing_admin_policy_enabled     = contains(local.configured_policies, "billing_admin")
}

data "aws_iam_policy" "aws_billing_read_only_access" {
  count = local.billing_read_only_policy_enabled ? 1 : 0

  arn = "arn:${local.aws_partition}:iam::aws:policy/AWSBillingReadOnlyAccess"
}

resource "aws_iam_policy" "billing_read_only" {
  count = local.billing_read_only_policy_enabled ? 1 : 0

  name   = format("%s-billing", module.this.id)
  policy = data.aws_iam_policy.aws_billing_read_only_access[0].policy

  tags = module.this.tags
}

data "aws_iam_policy" "aws_billing_admin_access" {
  count = local.billing_admin_policy_enabled ? 1 : 0

  arn = "arn:${local.aws_partition}:iam::aws:policy/job-function/Billing"
}

data "aws_iam_policy_document" "billing_admin_access_aggregated" {
  count = local.billing_admin_policy_enabled ? 1 : 0

  source_policy_documents = [
    data.aws_iam_policy.aws_billing_admin_access[0].policy,
    data.aws_iam_policy.aws_support_access[0].policy,
  ]
}

resource "aws_iam_policy" "billing_admin" {
  count = local.billing_admin_policy_enabled ? 1 : 0

  name   = format("%s-billing-admin", module.this.id)
  policy = data.aws_iam_policy_document.billing_admin_access_aggregated[0].json

  tags = module.this.tags
}

locals {
  support_policy_enabled = contains(local.configured_policies, "support")
}

data "aws_iam_policy_document" "support_access_trusted_advisor" {
  count = local.support_policy_enabled ? 1 : 0

  statement {
    sid    = "AllowTrustedAdvisor"
    effect = "Allow"
    actions = [
      "trustedadvisor:Describe*",
    ]

    resources = [
      "arn:${local.aws_partition}:trustedadvisor:*:*:checks/*",
    ]
  }
}

data "aws_iam_policy" "aws_support_access" {
  count = local.support_policy_enabled ? 1 : 0

  arn = "arn:${local.aws_partition}:iam::aws:policy/AWSSupportAccess"
}

data "aws_iam_policy_document" "support_access_aggregated" {
  count = local.support_policy_enabled ? 1 : 0

  source_policy_documents = [
    data.aws_iam_policy.aws_support_access[0].policy,
    data.aws_iam_policy_document.support_access_trusted_advisor[0].json
  ]
}

resource "aws_iam_policy" "support" {
  count = local.support_policy_enabled ? 1 : 0

  name   = format("%s-support", module.this.id)
  policy = data.aws_iam_policy_document.support_access_aggregated[0].json

  tags = module.this.tags
}

provider "aws" {
  region = var.region

  profile = module.iam_roles.profiles_enabled ? coalesce(var.import_profile_name, module.iam_roles.terraform_profile_name) : null

  dynamic "assume_role" {
    for_each = var.import_role_arn == null ? (module.iam_roles.org_role_arn != null ? [true] : []) : ["import"]
    content {
      role_arn = coalesce(var.import_role_arn, module.iam_roles.org_role_arn)
    }
  }
}

module "iam_roles" {
  source     = "../../modules/account-map/modules/iam-roles"
  privileged = true
  context    = module.this.context
}

variable "import_profile_name" {
  type        = string
  default     = null
  description = "AWS Profile name to use when importing a resource"
}

variable "import_role_arn" {
  description = "IAM Role ARN to use when importing a resource"
  type        = string
  default     = null
}

module "sso" {
  source = "git::https://github.com/cloudposse/terraform-yaml-stack-config.git//modules/remote-state?ref=0.22.2"

  component  = "sso"
  privileged = true

  ignore_errors = true

  defaults = {
    saml_provider_arns = []
  }

  context = module.this.context
}

variable "region" {
  type        = string
  description = "AWS Region"
}

variable "iam_primary_roles_account_name" {
  description = "The name of the account where the IAM primary roles are provisioned"
  type        = string
  default     = "identity"
}

variable "roles" {
  description = "A roles map to configure the accounts."
  type = map(object({
    enabled = bool

    denied_permission_sets  = list(string)
    denied_primary_roles    = list(string)
    denied_role_arns        = list(string)
    max_session_duration    = number
    role_description        = string
    role_policy_arns        = list(string)
    sso_login_enabled       = bool
    trusted_permission_sets = list(string)
    trusted_primary_roles   = list(string)
    trusted_role_arns       = list(string)
  }))
}

terraform {
  required_version = ">= 1.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
}