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
  source = "git::https://github.com/cloudposse/terraform-null-label.git?ref=488ab91e34a24a86957e397d9f7262ec5925586a"

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
  enabled     = module.this.enabled
  account_map = module.account_map.outputs.full_account_map

  current_account_id                     = one(data.aws_caller_identity.this[*].account_id)
  member_account_id_list                 = [for a in keys(local.account_map) : (local.account_map[a]) if local.account_map[a] != local.current_account_id]
  org_delegated_administrator_account_id = local.account_map[var.delegated_administrator_account_name]
  org_management_account_id              = var.organization_management_account_name == null ? local.account_map[module.account_map.outputs.root_account_account_name] : local.account_map[var.organization_management_account_name]
  is_org_delegated_administrator_account = local.current_account_id == local.org_delegated_administrator_account_id
  is_org_management_account              = local.current_account_id == local.org_management_account_id

  create_sns_topic           = local.enabled && var.create_sns_topic
  create_guardduty_collector = local.enabled && ((local.is_org_delegated_administrator_account && !var.admin_delegated) || local.is_org_management_account)
  create_org_delegation      = local.enabled && local.is_org_management_account
  create_org_configuration   = local.enabled && local.is_org_delegated_administrator_account && var.admin_delegated
}

data "aws_caller_identity" "this" {
  count = local.enabled ? 1 : 0
}

# If we are are in the AWS Org management account, delegate GuardDuty to the org administrator account
# (usually the security account)
resource "aws_guardduty_organization_admin_account" "this" {
  count = local.create_org_delegation ? 1 : 0

  admin_account_id = local.org_delegated_administrator_account_id
}

# If we are are in the AWS Org designated administrator account, enable the GuardDuty detector and optionally create an
# SNS topic for notifications and CloudWatch event rules for findings
module "guardduty" {
  count  = local.create_guardduty_collector ? 1 : 0
  source = "git::https://github.com/cloudposse/terraform-aws-guardduty.git?ref=2d57d84a7b436e1f1e10d1c4c1a0e8e8e6e5c4b3"

  finding_publishing_frequency              = var.finding_publishing_frequency
  create_sns_topic                          = local.create_sns_topic
  findings_notification_arn                 = var.findings_notification_arn
  subscribers                               = var.subscribers
  enable_cloudwatch                         = var.cloudwatch_enabled
  cloudwatch_event_rule_pattern_detail_type = var.cloudwatch_event_rule_pattern_detail_type
  s3_protection_enabled                     = var.s3_protection_enabled

  context = module.this.context
}

# If we are are in the AWS Org designated administrator account, set the AWS Org-wide GuardDuty configuration by
# configuring all other accounts to send their GuardDuty findings to the detector in this account.
#
# This also configures the various Data Sources.
resource "awsutils_guardduty_organization_settings" "this" {
  count = local.create_org_configuration ? 1 : 0

  member_accounts = local.member_account_id_list
  detector_id     = module.guardduty_delegated_detector[0].outputs.guardduty_detector_id
}

resource "aws_guardduty_organization_configuration" "this" {
  count = local.create_org_configuration ? 1 : 0

  auto_enable_organization_members = var.auto_enable_organization_members
  detector_id                      = module.guardduty_delegated_detector[0].outputs.guardduty_detector_id

  datasources {
    s3_logs {
      auto_enable = var.s3_protection_enabled
    }
    kubernetes {
      audit_logs {
        enable = var.kubernetes_audit_logs_enabled
      }
    }
    malware_protection {
      scan_ec2_instance_with_findings {
        ebs_volumes {
          auto_enable = var.malware_protection_scan_ec2_ebs_volumes_enabled
        }
      }
    }
  }
}

resource "aws_guardduty_detector_feature" "this" {
  for_each = { for k, v in var.detector_features : k => v if local.create_org_configuration }

  detector_id = module.guardduty_delegated_detector[0].outputs.guardduty_detector_id
  name        = each.value.feature_name
  status      = each.value.status

  dynamic "additional_configuration" {
    for_each = each.value.additional_configuration != null ? [each.value.additional_configuration] : []
    content {
      name   = additional_configuration.value.addon_name
      status = additional_configuration.value.status
    }
  }
}


output "delegated_administrator_account_id" {
  value       = local.org_delegated_administrator_account_id
  description = "The AWS Account ID of the AWS Organization delegated administrator account"
}

output "guardduty_detector_arn" {
  value       = local.create_guardduty_collector ? try(module.guardduty[0].guardduty_detector.arn, null) : null
  description = "The ARN of the GuardDuty detector created by the component"
}

output "guardduty_detector_id" {
  value       = local.create_guardduty_collector ? try(module.guardduty[0].guardduty_detector.id, null) : null
  description = "The ID of the GuardDuty detector created by the component"
}

output "sns_topic_name" {
  value       = local.create_guardduty_collector ? try(module.guardduty[0].sns_topic.name, null) : null
  description = "The name of the SNS topic created by the component"
}

output "sns_topic_subscriptions" {
  value       = local.create_guardduty_collector ? try(module.guardduty[0].sns_topic_subscriptions, null) : null
  description = "The SNS topic subscriptions created by the component"
}


provider "aws" {
  region = var.region

  profile = !var.privileged && module.iam_roles.profiles_enabled ? module.iam_roles.terraform_profile_name : null
  dynamic "assume_role" {
    for_each = var.privileged || module.iam_roles.profiles_enabled || (module.iam_roles.terraform_role_arn == null) ? [] : ["role"]
    content {
      role_arn = module.iam_roles.terraform_role_arn
    }
  }
}

provider "awsutils" {
  region = var.region

  profile = !var.privileged && module.iam_roles.profiles_enabled ? module.iam_roles.terraform_profile_name : null
  dynamic "assume_role" {
    for_each = var.privileged || module.iam_roles.profiles_enabled || (module.iam_roles.terraform_role_arn == null) ? [] : ["role"]
    content {
      role_arn = module.iam_roles.terraform_role_arn
    }
  }
}

module "iam_roles" {
  source     = "../account-map/modules/iam-roles"
  privileged = var.privileged

  context = module.this.context
}


module "account_map" {
  source = "git::https://github.com/cloudposse/terraform-yaml-stack-config.git//modules/remote-state?ref=93e2f3a8c7d1b4567890abcdef1234567890abcd"

  component   = "account-map"
  tenant      = var.account_map_tenant != "" ? var.account_map_tenant : module.this.tenant
  stage       = var.root_account_stage
  environment = var.global_environment
  privileged  = var.privileged

  context = module.this.context
}

module "guardduty_delegated_detector" {
  source = "git::https://github.com/cloudposse/terraform-yaml-stack-config.git//modules/remote-state?ref=93e2f3a8c7d1b4567890abcdef1234567890abcd"

  # If we are creating the delegated detector (because we are in the delegated admin account), then don't try to lookup
  # the delegated detector ID from remote state
  count = local.create_guardduty_collector ? 0 : 1

  component  = "${var.delegated_admininstrator_component_name}/${module.this.environment}"
  stage      = replace(var.delegated_administrator_account_name, "${module.this.tenant}-", "")
  privileged = var.privileged

  context = module.this.context
}


variable "account_map_tenant" {
  type        = string
  default     = "core"
  description = "The tenant where the `account_map` component required by remote-state is deployed"
}

variable "admin_delegated" {
  type        = bool
  default     = false
  description = <<DOC
  A flag to indicate if the AWS Organization-wide settings should be created. This can only be done after the GuardDuty
  Administrator account has already been delegated from the AWS Org Management account (usually 'root'). See the
  Deployment section of the README for more information.
  DOC
}

variable "auto_enable_organization_members" {
  type        = string
  default     = "NEW"
  description = <<-DOC
  Indicates the auto-enablement configuration of GuardDuty for the member accounts in the organization. Valid values are `ALL`, `NEW`, `NONE`.

  For more information, see:
  https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/guardduty_organization_configuration#auto_enable_organization_members
  DOC

}

variable "cloudwatch_event_rule_pattern_detail_type" {
  type        = string
  default     = "GuardDuty Finding"
  description = <<-DOC
  The detail-type pattern used to match events that will be sent to SNS.

  For more information, see:
  https://docs.aws.amazon.com/AmazonCloudWatch/latest/events/CloudWatchEventsandEventPatterns.html
  https://docs.aws.amazon.com/eventbridge/latest/userguide/event-types.html
  https://docs.aws.amazon.com/guardduty/latest/ug/guardduty_findings_cloudwatch.html
  DOC
}

variable "create_sns_topic" {
  type        = bool
  default     = false
  description = <<-DOC
  Flag to indicate whether an SNS topic should be created for notifications. If you want to send findings to a new SNS
  topic, set this to true and provide a valid configuration for subscribers.
  DOC
}

variable "delegated_admininstrator_component_name" {
  type        = string
  default     = "guardduty/delegated-administrator"
  description = "The name of the component that created the GuardDuty detector."
}

variable "delegated_administrator_account_name" {
  type        = string
  default     = "core-security"
  description = "The name of the account that is the AWS Organization Delegated Administrator account"
}

variable "cloudwatch_enabled" {
  type        = bool
  default     = false
  description = <<-DOC
  Flag to indicate whether CloudWatch logging should be enabled for GuardDuty
  DOC
}

variable "finding_publishing_frequency" {
  type        = string
  default     = null
  description = <<-DOC
  The frequency of notifications sent for finding occurrences. If the detector is a GuardDuty member account, the value
  is determined by the GuardDuty master account and cannot be modified, otherwise it defaults to SIX_HOURS.

  For standalone and GuardDuty master accounts, it must be configured in Terraform to enable drift detection.
  Valid values for standalone and master accounts: FIFTEEN_MINUTES, ONE_HOUR, SIX_HOURS."

  For more information, see:
  https://docs.aws.amazon.com/guardduty/latest/ug/guardduty_findings_cloudwatch.html#guardduty_findings_cloudwatch_notification_frequency
  DOC
}

variable "findings_notification_arn" {
  default     = null
  type        = string
  description = <<-DOC
  The ARN for an SNS topic to send findings notifications to. This is only used if create_sns_topic is false.
  If you want to send findings to an existing SNS topic, set this to the ARN of the existing topic and set
  create_sns_topic to false.
  DOC
}

variable "global_environment" {
  type        = string
  default     = "gbl"
  description = "Global environment name"
}

variable "kubernetes_audit_logs_enabled" {
  type        = bool
  default     = false
  description = <<-DOC
  If `true`, enables Kubernetes audit logs as a data source for Kubernetes protection.

  For more information, see:
  https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/guardduty_detector#audit_logs
  DOC
}

variable "malware_protection_scan_ec2_ebs_volumes_enabled" {
  type        = bool
  default     = false
  description = <<-DOC
  Configure whether Malware Protection is enabled as data source for EC2 instances EBS Volumes in GuardDuty.

  For more information, see:
  https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/guardduty_detector#malware-protection
  DOC
}

variable "organization_management_account_name" {
  type        = string
  default     = null
  description = "The name of the AWS Organization management account"
}

variable "privileged" {
  type        = bool
  default     = false
  description = "true if the default provider already has access to the backend"
}

variable "region" {
  type        = string
  description = "AWS Region"
}

variable "root_account_stage" {
  type        = string
  default     = "root"
  description = <<-DOC
  The stage name for the Organization root (management) account. This is used to lookup account IDs from account names
  using the `account-map` component.
  DOC
}

variable "s3_protection_enabled" {
  type        = bool
  default     = true
  description = <<-DOC
  If `true`, enables S3 protection.

  For more information, see:
  https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/guardduty_detector#s3-logs
  DOC
}

variable "subscribers" {
  type = map(object({
    protocol               = string
    endpoint               = string
    endpoint_auto_confirms = bool
    raw_message_delivery   = bool
  }))
  default     = {}
  description = <<-DOC
  A map of subscription configurations for SNS topics

  For more information, see:
  https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sns_topic_subscription#argument-reference

  protocol:
    The protocol to use. The possible values for this are: sqs, sms, lambda, application. (http or https are partially
    supported, see link) (email is an option but is unsupported in terraform, see link).
  endpoint:
    The endpoint to send data to, the contents will vary with the protocol. (see link for more information)
  endpoint_auto_confirms:
    Boolean indicating whether the end point is capable of auto confirming subscription e.g., PagerDuty. Default is
    false.
  raw_message_delivery:
    Boolean indicating whether or not to enable raw message delivery (the original message is directly passed, not
    wrapped in JSON with the original message in the message property). Default is false.
  DOC
}

variable "detector_features" {
  type = map(object({
    feature_name = string
    status       = string
    additional_configuration = optional(object({
      addon_name = string
      status     = string
    }), null)
  }))
  default     = {}
  nullable    = false
  description = <<-DOC
  A map of detector features for streaming foundational data sources to detect communication with known malicious domains and IP addresses and identify anomalous behavior.

  For more information, see:
  https://docs.aws.amazon.com/guardduty/latest/ug/guardduty-features-activation-model.html#guardduty-features

  feature_name:
    The name of the detector feature. Possible values include: S3_DATA_EVENTS, EKS_AUDIT_LOGS, EBS_MALWARE_PROTECTION, RDS_LOGIN_EVENTS, EKS_RUNTIME_MONITORING, LAMBDA_NETWORK_LOGS, RUNTIME_MONITORING. Specifying both EKS Runtime Monitoring (EKS_RUNTIME_MONITORING) and Runtime Monitoring (RUNTIME_MONITORING) will cause an error. You can add only one of these two features because Runtime Monitoring already includes the threat detection for Amazon EKS resources. For more information, see: https://docs.aws.amazon.com/guardduty/latest/APIReference/API_DetectorFeatureConfiguration.html.
  status:
    The status of the detector feature. Valid values include: ENABLED or DISABLED.
  additional_configuration:
    Optional information about the additional configuration for a feature in your GuardDuty account. For more information, see: https://docs.aws.amazon.com/guardduty/latest/APIReference/API_DetectorAdditionalConfiguration.html.
  addon_name:
    The name of the add-on for which the configuration applies. Possible values include: EKS_ADDON_MANAGEMENT, ECS_FARGATE_AGENT_MANAGEMENT, and EC2_AGENT_MANAGEMENT. For more information, see: https://docs.aws.amazon.com/guardduty/latest/APIReference/API_DetectorAdditionalConfiguration.html.
  status:
    The status of the add-on. Valid values include: ENABLED or DISABLED.
  DOC
}


terraform {
  required_version = ">= 1.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }

    awsutils = {
      source  = "cloudposse/awsutils"
      version = ">= 0.16.0"
    }
  }
}