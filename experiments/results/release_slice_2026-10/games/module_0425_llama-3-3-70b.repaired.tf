locals {
  # If you have custom permission sets, override this declaration by creating
  # a file called `additional-permission-sets_override.tf`.
  # Then add the custom permission sets to the overridable_additional_permission_sets in that file.
  # See the README for more details.
  overridable_additional_permission_sets = [
    # Example
    # local.audit_manager_permission_set,
  ]
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
  version = "0.25.0" # requires Terraform >= 0.13.0

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
  enabled = module.this.enabled

  account_map  = module.account_map.outputs.full_account_map
  root_account = local.account_map[module.account_map.outputs.root_account_account_name]

  account_assignments_groups = flatten([
    for account_key, account in var.account_assignments : [
      for principal_key, principal in account.groups : [
        for permissions_key, permissions in principal.permission_sets :
        {
          account             = local.account_map[account_key]
          permission_set_arn  = module.permission_sets.permission_sets[permissions].arn
          permission_set_name = module.permission_sets.permission_sets[permissions].name
          principal_name      = principal_key
          principal_type      = "GROUP"
        }
      ]
    ] if lookup(account, "groups", null) != null
  ])
  # Remove root because the identity org role cannot provision root assignments
  account_assignments_groups_no_root = [
    for val in local.account_assignments_groups :
    val
    if val.account != local.root_account
  ]
  account_assignments_groups_only_root = [
    for val in local.account_assignments_groups :
    val
    if val.account == local.root_account
  ]
  account_assignments_users = flatten([
    for account_key, account in var.account_assignments : [
      for principal_key, principal in account.users : [
        for permissions_key, permissions in principal.permission_sets :
        {
          account             = local.account_map[account_key]
          permission_set_arn  = module.permission_sets.permission_sets[permissions].arn
          permission_set_name = module.permission_sets.permission_sets[permissions].name
          principal_name      = principal_key
          principal_type      = "USER"
        }
      ]
    ] if lookup(account, "users", null) != null
  ])
  account_assignments_users_no_root = [
    for val in local.account_assignments_users :
    val
    if val.account != local.root_account
  ]
  account_assignments_users_only_root = [
    for val in local.account_assignments_users :
    val
    if val.account == local.root_account
  ]

  account_assignments      = concat(local.account_assignments_groups_no_root, local.account_assignments_users_no_root)
  account_assignments_root = concat(local.account_assignments_groups_only_root, local.account_assignments_users_only_root)

  aws_partition = data.aws_partition.current.partition
}

data "aws_ssoadmin_instances" "this" {}

data "aws_partition" "current" {}

resource "aws_identitystore_group" "manual" {
  for_each = toset(var.groups)

  display_name = each.key
  description  = "Group created with Terraform"

  identity_store_id = tolist(data.aws_ssoadmin_instances.this.identity_store_ids)[0]
}

module "permission_sets" {
  source  = "cloudposse/sso/aws//modules/permission-sets"
  version = "1.1.1"

  permission_sets = concat(
    local.overridable_additional_permission_sets,
    local.administrator_access_permission_set,
    local.billing_administrator_access_permission_set,
    local.billing_read_only_access_permission_set,
    local.dns_administrator_access_permission_set,
    local.identity_access_permission_sets,
    local.poweruser_access_permission_set,
    local.read_only_access_permission_set,
    local.terraform_update_access_permission_set,
  )

  context = module.this.context

  depends_on = [
    aws_identitystore_group.manual
  ]
}

module "sso_account_assignments" {
  source  = "cloudposse/sso/aws//modules/account-assignments"
  version = "1.1.1"

  account_assignments = local.account_assignments
  context             = module.this.context

  depends_on = [
    aws_identitystore_group.manual
  ]
}

module "sso_account_assignments_root" {
  source  = "cloudposse/sso/aws//modules/account-assignments"
  version = "1.1.1"

  providers = {
    aws = aws.root
  }

  account_assignments = local.account_assignments_root
  context             = module.this.context

  depends_on = [
    aws_identitystore_group.manual
  ]
}


output "permission_sets" {
  value       = module.permission_sets.permission_sets
  description = "Permission sets"
}

output "sso_account_assignments" {
  value       = module.sso_account_assignments.assignments
  description = "SSO account assignments"
}

output "group_ids" {
  value       = { for group_key, group_output in aws_identitystore_group.manual : group_key => group_output.group_id }
  description = "Group IDs created for Identity Center"
}


locals {
  administrator_access_permission_set = [{
    name                                = "AdministratorAccess",
    description                         = "Allow Full Administrator access to the account",
    relay_state                         = "",
    session_duration                    = "",
    tags                                = {},
    inline_policy                       = ""
    policy_attachments                  = ["arn:${local.aws_partition}:iam::aws:policy/AdministratorAccess"]
    customer_managed_policy_attachments = []
  }]
}


locals {
  billing_administrator_access_permission_set = [{
    name             = "BillingAdministratorAccess",
    description      = "Grants permissions for billing and cost management. This includes viewing account usage and viewing and modifying budgets and payment methods.",
    relay_state      = "https://console.aws.amazon.com/billing/",
    session_duration = "",
    tags             = {},
    inline_policy    = ""
    policy_attachments = [
      "arn:${local.aws_partition}:iam::aws:policy/job-function/Billing",
      "arn:${local.aws_partition}:iam::aws:policy/AWSSupportAccess",
    ]
    customer_managed_policy_attachments = []
  }]
}


locals {
  billing_read_only_access_permission_set = [{
    name             = "BillingReadOnlyAccess",
    description      = "Allow users to view bills in the billing console",
    relay_state      = "",
    session_duration = "",
    tags             = {},
    inline_policy    = ""
    policy_attachments = [
      "arn:${local.aws_partition}:iam::aws:policy/AWSBillingReadOnlyAccess",
      "arn:${local.aws_partition}:iam::aws:policy/AWSSupportAccess",
    ]
    customer_managed_policy_attachments = []
  }]
}


data "aws_iam_policy_document" "dns_administrator_access" {
  statement {
    sid    = "AllowDNS"
    effect = "Allow"
    actions = [
      "route53:ChangeResourceRecordSets",
      "route53:CreateHealthCheck",
      "route53:CreateTrafficPolicy",
      "route53:CreateTrafficPolicyInstance",
      "route53:CreateTrafficPolicyVersion",
      "route53:DeleteHealthCheck",
      "route53:DeleteTrafficPolicy",
      "route53:DeleteTrafficPolicyInstance",
      "route53:Get*",
      "route53:List*",
      "route53:UpdateHealthCheck",
      "route53:UpdateTrafficPolicyComment",
      "route53:UpdateTrafficPolicyInstance",
      "route53domains:List*",
    ]

    resources = [
      "arn:${local.aws_partition}:route53:::hostedzone/*",
      "arn:${local.aws_partition}:route53:::trafficpolicy/*",
      "arn:${local.aws_partition}:route53:::trafficpolicyinstance/*",
      "arn:${local.aws_partition}:route53domains:::domain/*",
    ]
  }
}

locals {
  dns_administrator_access_permission_set = [{
    name                                = "DNSRecordAdministratorAccess",
    description                         = "Allow DNS Record Administrator access to the account, but not zone administration",
    relay_state                         = "https://console.aws.amazon.com/route53/",
    session_duration                    = "",
    tags                                = {},
    inline_policy                       = data.aws_iam_policy_document.dns_administrator_access.json,
    policy_attachments                  = ["arn:${local.aws_partition}:iam::aws:policy/AWSSupportAccess"]
    customer_managed_policy_attachments = []
  }]
}



# This file generates a permission set for each role specified in var.target_identity_roles
# which is named "Identity<Role>TeamAccess" and grants access to only that role,
# plus ViewOnly access because it is difficult to navigate without any access at all.

data "aws_iam_policy_document" "assume_aws_team" {
  for_each = local.enabled ? var.aws_teams_accessible : []

  statement {
    sid = "RoleAssumeRole"

    effect = "Allow"
    actions = [
      "sts:AssumeRole",
      "sts:SetSourceIdentity",
      "sts:TagSession",
    ]

    resources = [
      "arn:${local.aws_partition}:iam::${local.account_map[module.iam_roles.global_account_name].account_id}:role/${each.value}",
    ]

    condition {
      test     = "StringLike"
      variable = "iam:ResourceTag/Name"
      values   = [each.value]
    }
  }
}

module "role_map" {
  source = "../account-map/modules/roles-to-principals"

  teams      = var.aws_teams_accessible
  privileged = var.privileged

  context = module.this.context
}

locals {
  identity_access_permission_sets = [for role in var.aws_teams_accessible : {
    name                                = module.role_map.team_permission_set_name_map[role],
    description                         = format("Allow user to assume the %s Team role in the Identity account, which allows access to other accounts", replace(title(role), "-", ""))
    relay_state                         = "",
    session_duration                    = "",
    tags                                = {},
    inline_policy                       = data.aws_iam_policy_document.assume_aws_team[role].json
    policy_attachments                  = ["arn:${local.aws_partition}:iam::aws:policy/job-function/ViewOnlyAccess"]
    customer_managed_policy_attachments = []
  }]
}


locals {
  poweruser_access_permission_set = [{
    name             = "PowerUserAccess",
    description      = "Allow Poweruser access to the account",
    relay_state      = "",
    session_duration = "",
    tags             = {},
    inline_policy    = ""
    policy_attachments = [
      "arn:${local.aws_partition}:iam::aws:policy/PowerUserAccess",
      "arn:${local.aws_partition}:iam::aws:policy/AWSSupportAccess",
    ]
    customer_managed_policy_attachments = []
  }]
}


locals {
  read_only_access_permission_set = [{
    name             = "ReadOnlyAccess",
    description      = "Allow Read Only access to the account",
    relay_state      = "",
    session_duration = "",
    tags             = {},
    inline_policy    = data.aws_iam_policy_document.eks_read_only.json,
    policy_attachments = [
      "arn:${local.aws_partition}:iam::aws:policy/ReadOnlyAccess",
      "arn:${local.aws_partition}:iam::aws:policy/AWSSupportAccess"
    ]
    customer_managed_policy_attachments = []
  }]
}

data "aws_iam_policy_document" "eks_read_only" {
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
      "arn:${local.aws_partition}:eks:*:*:cluster/*",
    ]
  }
}


variable "tfstate_environment_name" {
  type        = string
  description = "The name of the environment where `tfstate-backend` is provisioned. If not set, the TerraformUpdateAccess permission set will not be created."
  default     = null
}

locals {
  tf_update_access_enabled = var.tfstate_environment_name != null && module.this.enabled
}

module "tfstate" {
  source  = "cloudposse/stack-config/yaml//modules/remote-state"
  version = "1.5.0"

  bypass = !local.tf_update_access_enabled

  component   = "tfstate-backend"
  environment = var.tfstate_environment_name
  stage       = module.iam_roles.global_stage_name
  privileged  = var.privileged

  context = module.this.context
}

data "aws_iam_policy_document" "terraform_update_access" {
  count = local.tf_update_access_enabled ? 1 : 0

  statement {
    sid     = "TerraformStateBackendS3Bucket"
    effect  = "Allow"
    actions = ["s3:ListBucket", "s3:GetObject", "s3:PutObject"]
    resources = module.this.enabled ? [
      module.tfstate.outputs.tfstate_backend_s3_bucket_arn,
      "${module.tfstate.outputs.tfstate_backend_s3_bucket_arn}/*"
    ] : []
  }
  statement {
    sid       = "TerraformStateBackendDynamoDbTable"
    effect    = "Allow"
    actions   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:DeleteItem"]
    resources = module.this.enabled ? [module.tfstate.outputs.tfstate_backend_dynamodb_table_arn] : []
  }
}

locals {
  terraform_update_access_permission_set = local.tf_update_access_enabled ? [{
    name                                = "TerraformUpdateAccess",
    description                         = "Allow access to Terraform state sufficient to make changes",
    relay_state                         = "",
    session_duration                    = "PT1H", # One hour, maximum allowed for chained assumed roles
    tags                                = {},
    inline_policy                       = one(data.aws_iam_policy_document.terraform_update_access[*].json),
    policy_attachments                  = []
    customer_managed_policy_attachments = []
  }] : []
}


# This component is unusual in that part of it must be deployed to the `root`
# account. You have the option of where to deploy the remaining part, and
# Cloud Posse recommends you deploy it also to the `root` account, however
# it can be deployed to the `identity` account instead. In the discussion
# below, when we talk about where this module is being deployed, we are
# referring to the part of the module that is not deployed to the `root`
# account and is configured by setting `stage` etc..

# If you have Dynamic Terraform Roles enabled, leave the backend `role_arn` at
# its default value. If deploying only to the `root` account, leave `privileged: false`
# and use either SuperAdmin or an appropriate `aws-team` (such as `managers`).
# If deploying to the `identity` account, set `privileged: true`
# and use SuperAdmin or any other role in the `root` account with Admin access.
#
# For those not using dynamic Terraform roles:
#
# Set the stack configuration for this component to set `privileged: true`
# and backend `role_arn` to `null`, and deploy it using either the SuperAdmin
# role or any other role in the `root` account with Admin access.
#
# If you are deploying this to the "identity" account and have a team empowered
# to deploy to both the "identity" and "root" accounts, then you have the option to set
# `privileged: false` and leave the backend `role_arn` at its default value, but
# then SuperAdmin will not be able to deploy this component,
# only the team with access to both accounts will be able to deploy it.
#

provider "aws" {
  region = var.region

  profile = !var.privileged && module.iam_roles.profiles_enabled ? module.iam_roles.terraform_profile_name : null
  dynamic "assume_role" {
    for_each = !var.privileged && module.iam_roles.profiles_enabled ? [] : (
      var.privileged ? compact([module.iam_roles.org_role_arn]) : compact([module.iam_roles.terraform_role_arn])
    )
    content {
      role_arn = assume_role.value
    }
  }
}


module "iam_roles" {
  source     = "../account-map/modules/iam-roles"
  privileged = var.privileged

  context = module.this.context
}

provider "aws" {
  alias  = "root"
  region = var.region

  profile = !var.privileged && module.iam_roles_root.profiles_enabled ? module.iam_roles_root.terraform_profile_name : null
  dynamic "assume_role" {
    for_each = !var.privileged && module.iam_roles_root.profiles_enabled ? [] : (
      var.privileged ? compact([module.iam_roles_root.org_role_arn]) : compact([module.iam_roles_root.terraform_role_arn])
    )
    content {
      role_arn = assume_role.value
    }
  }
}


module "iam_roles_root" {
  source = "../account-map/modules/iam-roles"

  privileged  = var.privileged
  tenant      = module.iam_roles.global_tenant_name
  stage       = module.iam_roles.global_stage_name
  environment = module.iam_roles.global_environment_name

  context = module.this.context
}


module "account_map" {
  source  = "cloudposse/stack-config/yaml//modules/remote-state"
  version = "1.5.0"

  component   = "account-map"
  environment = module.iam_roles.global_environment_name
  stage       = module.iam_roles.global_stage_name
  tenant      = module.iam_roles.global_tenant_name
  privileged  = var.privileged

  context = module.this.context
}


variable "region" {
  type        = string
  description = "AWS Region"
}

variable "privileged" {
  type        = bool
  description = "True if the user running the Terraform command already has access to the Terraform backend"
  default     = false
}

variable "account_assignments" {
  type = map(map(map(object({
    permission_sets = list(string)
    }
  ))))
  description = <<-EOT
    Enables access to permission sets for users and groups in accounts, in the following structure:

    ```yaml
    <account-name>:
      groups:
        <group-name>:
          permission_sets:
            - <permission-set-name>
      users:
        <user-name>:
          permission_sets:
            - <permission-set-name>
    ```

    EOT
  default     = {}
}

variable "aws_teams_accessible" {
  type        = set(string)
  description = <<-EOT
    List of IAM roles (e.g. ["admin", "terraform"]) for which to create permission
    sets that allow the user to assume that role. Named like
    admin -> IdentityAdminTeamAccess
    EOT
  default     = []
}

variable "groups" {
  type        = list(string)
  description = <<-EOT
    List of AWS Identity Center Groups to be created with the AWS API.

    When provisioning the Google Workspace Integration with AWS, Groups need to be created with API in order for automatic provisioning to work as intended.
    EOT
  default     = []
}


terraform {
  required_version = ">= 1.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 4.0"
    }
  }
}