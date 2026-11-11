locals {
  overridable_additional_permission_sets = [
  ]
}

module "this" {
  source  = "git::https://github.com/cloudposse/terraform-null-label.git?ref=4ae8b9b8342368d38a0455b7b9cb7c1ff3fde298"
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

  validation {
    condition     = var.id_length_limit == null ? true : var.id_length_limit >= 6 || var.id_length_limit == 0
    error_message = "The id_length_limit must be >= 6 if supplied (not null), or 0 for unlimited length."
  }
}

variable "label_key_case" {
  type        = string
  default     = null

  validation {
    condition     = var.label_key_case == null ? true : contains(["lower", "title", "upper"], var.label_key_case)
    error_message = "Allowed values: `lower`, `title`, `upper`."
  }
}

variable "label_value_case" {
  type        = string
  default     = null

  validation {
    condition     = var.label_value_case == null ? true : contains(["lower", "title", "upper", "none"], var.label_value_case)
    error_message = "Allowed values: `lower`, `title`, `upper`, `none`."
  }
}

variable "descriptor_formats" {
  type        = any
  default     = {}
}

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
  source  = "git::https://github.com/cloudposse/terraform-aws-sso.git//modules/permission-sets?ref=5a6e0350c3a0a8a3a3a3a3a3a3a3a3a3a3a3a3a"
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
  source  = "git::https://github.com/cloudposse/terraform-aws-sso.git//modules/account-assignments?ref=5a6e0350c3a0a8a3a3a3a3a3a3a3a3a3a3a3a3a"
  version = "1.1.1"

  account_assignments = local.account_assignments
  context             = module.this.context

  depends_on = [
    aws_identitystore_group.manual
  ]
}

module "sso_account_assignments_root" {
  source  = "git::https://github.com/cloudposse/terraform-aws-sso.git//modules/account-assignments?ref=5a6e0350c3a0a8a3a3a3a3a3a3a3a3a3a3a3a3a"
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
}

output "sso_account_assignments" {
  value       = module.sso_account_assignments.assignments
}

output "group_ids" {
  value       = { for group_key, group_output in aws_identitystore_group.manual : group_key => group_output.group_id }
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

    resources = ["*"]

    condition {
      test     = "Bool"
      variable = "aws:MultiFactorAuthPresent"
      values   = ["true"]
    }
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

    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "iam:ResourceTag/Name"
      values   = [format("%s-%s", module.role_prefix.id, each.value)]
    }

    condition {
      test     = "Bool"
      variable = "aws:MultiFactorAuthPresent"
      values   = ["true"]
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
      "arn:${local.aws_partition}:eks:*:*:cluster/*"
    ]
  }
}

variable "tfstate_environment_name" {
  type        = string
  default     = null
}

locals {
  tf_update_access_enabled = var.tfstate_environment_name != null && module.this.enabled
}

module "tfstate" {
  source  = "git::https://github.com/cloudposse/terraform-yaml-stack-config.git//modules/remote-state?ref=1a1dba0a2a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a"
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
    session_duration                    = "PT1H",
    tags                                = {},
    inline_policy                       = one(data.aws_iam_policy_document.terraform_update_access[*].json),
    policy_attachments                  = []
    customer_managed_policy_attachments = []
  }] : []
}

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
  source  = "git::https://github.com/cloudposse/terraform-yaml-stack-config.git//modules/remote-state?ref=1a1dba0a2a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a"
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
}

variable "privileged" {
  type        = bool
  default     = false
}

variable "account_assignments" {
  type = map(map(map(object({
    permission_sets = list(string)
    }
  ))))
  default     = {}
}

variable "aws_teams_accessible" {
  type        = set(string)
  default     = []
}

variable "groups" {
  type        = list(string)
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