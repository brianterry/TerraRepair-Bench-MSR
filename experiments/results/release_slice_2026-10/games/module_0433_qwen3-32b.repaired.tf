variable "request_acm_certificate" {
  type        = bool
  default     = true
  description = "Whether or not to create an ACM certificate"
}

locals {
  certificate_enabled = local.enabled && var.request_acm_certificate

  # Should this be set for all ACM certs or should be set differently per each ?
  alternative_names = [for zone in var.zone_config : format("*.%s.%s", zone.subdomain, zone.zone_name)]
}

module "acm" {
  for_each = local.zone_map

  source  = "cloudposse/acm-request-certificate/aws"
  version = "0.17.0"

  enabled = local.certificate_enabled

  domain_name = format("%s.%s", each.key, each.value)
  zone_id     = local.aws_route53_zone[each.key].zone_id

  process_domain_validation_options = true
  ttl                               = 300
  subject_alternative_names         = local.alternative_names

  certificate_authority_arn = local.certificate_enabled && local.private_ca_enabled ? module.private_ca[0].outputs.private_ca[var.certificate_authority_component_key].certificate_authority.arn : null
  validation_method         = local.certificate_enabled && local.private_ca_enabled ? null : "DNS"

  context    = module.this.context
  depends_on = [aws_route53_record.root_ns]
}

resource "aws_ssm_parameter" "acm_arn" {
  for_each = local.certificate_enabled ? local.zone_map : {}

  name        = format("/acm/%s.%s", each.key, each.value)
  value       = module.acm[each.key].arn
  description = "ACM certificate id"
  type        = "SecureString"
  overwrite   = true

  tags = module.this.tags
}

output "certificate" {
  value       = local.certificate_enabled ? module.acm : null
  description = "The ACM certificate information."
}

output "acm_ssm_parameter" {
  value       = aws_ssm_parameter.acm_arn
  description = "The SSM parameter for the ACM cert."
  sensitive   = true
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
  enabled  = module.this.enabled
  zone_map = zipmap(var.zone_config[*].subdomain, var.zone_config[*].zone_name)

  private_enabled = local.enabled && var.dns_private_zone_enabled
  public_enabled  = local.enabled && !local.private_enabled

  private_ca_enabled = local.private_enabled && var.certificate_authority_enabled

  aws_route53_zone = local.private_enabled ? aws_route53_zone.private : aws_route53_zone.default

  vpc_environment_names = toset(concat([var.vpc_primary_environment_name], var.vpc_secondary_environment_names))

  aws_partition = join("", data.aws_partition.current.*.partition)
}

resource "aws_route53_zone" "default" {
  for_each = local.public_enabled ? local.zone_map : {}

  name    = format("%s.%s", each.key, each.value)
  comment = format("DNS zone for %s.%s", each.key, each.value)

  query_logging_config {
    cloudwatch_logs_log_group_arn = var.dns_query_logging_enabled ? aws_cloudwatch_log_group.dns_logs.arn : null
    destination = var.dns_query_logging_enabled ? "cloudwatch-logs" : null
  }

  tags = module.this.tags
}

resource "aws_route53_zone" "private" {
  for_each = local.private_enabled ? local.zone_map : {}

  name    = format("%s.%s", each.key, each.value)
  comment = format("DNS zone for %s.%s", each.key, each.value)

  # The reason why this isn't in the original route53 zone is because this shows up as an update
  # when the aws provider should replace it. Using a separate resource allows the user to toggle
  # between private and public without manual targeted destroys.
  # See: https://github.com/hashicorp/terraform-provider-aws/issues/7614
  dynamic "vpc" {
    for_each = local.private_enabled ? [true] : []

    content {
      vpc_id = module.vpc[var.vpc_primary_environment_name].outputs.vpc_id
    }
  }

  query_logging_config {
    cloudwatch_logs_log_group_arn = var.dns_query_logging_enabled ? aws_cloudwatch_log_group.dns_logs.arn : null
    destination = var.dns_query_logging_enabled ? "cloudwatch-logs" : null
  }

  tags = module.this.tags

  # Prevent the deletion of associated VPCs after
  # the initial creation. See documentation on
  # aws_route53_zone_association for details
  # See https://github.com/hashicorp/terraform-provider-aws/issues/14872#issuecomment-682008493
  lifecycle {
    ignore_changes = [vpc]
  }
}

module "utils" {
  source  = "cloudposse/utils/aws"
  version = "1.3.0"
}

resource "aws_route53_zone_association" "secondary" {
  for_each = local.private_enabled && length(var.vpc_secondary_environment_names) > 0 ? toset(var.vpc_secondary_environment_names) : toset([])

  zone_id    = join("", local.aws_route53_zone.*.zone_id)
  vpc_id     = module.vpc[each.value].outputs.vpc_id
  vpc_region = module.utils.region_az_alt_code_maps[format("from_%s", var.vpc_region_abbreviation_type)][each.value]
}

data "aws_partition" "current" {
  count = local.enabled ? 1 : 0
}

resource "aws_shield_protection" "shield_protection" {
  for_each = local.enabled && var.aws_shield_protection_enabled ? local.aws_route53_zone : {}

  name         = local.aws_route53_zone[each.key].name
  resource_arn = format("arn:%s:route53:::hostedzone/%s", local.aws_partition, local.aws_route53_zone[each.key].id)

  tags = module.this.tags
}

resource "aws_route53_record" "soa" {
  for_each = local.enabled ? local.aws_route53_zone : {}

  allow_overwrite = true
  name            = local.aws_route53_zone[each.key].name
  type            = "SOA"
  ttl             = "60"
  zone_id         = local.aws_route53_zone[each.key].zone_id

  records = [
    format("${local.aws_route53_zone[each.key].name_servers[0]}%s %s", local.public_enabled ? "." : "", var.dns_soa_config)
  ]
}

data "aws_route53_zone" "root_zone" {
  for_each = local.enabled ? local.zone_map : {}
  provider = aws.primary

  name         = format("%s.", each.value)
  private_zone = false
}

resource "aws_route53_record" "root_ns" {
  for_each = local.enabled ? data.aws_route53_zone.root_zone : {}
  provider = aws.primary

  allow_overwrite = true
  name            = each.key
  records         = local.aws_route53_zone[each.key].name_servers
  type            = "NS"
  ttl             = "30"
  zone_id         = data.aws_route53_zone.root_zone[each.key].zone_id
}


output "zones" {
  value       = local.aws_route53_zone
  description = "Subdomain and zone config"
}

output "default_domain_name" {
  description = "Default root domain name (e.g. dev.example.net) for the cluster"
  value       = join(".", [var.zone_config[0].subdomain, var.zone_config[0].zone_name])
}

output "default_dns_zone_id" {
  description = "Default root DNS zone ID for the cluster"
  value       = local.aws_route53_zone[var.zone_config[0].subdomain].zone_id
}

output "route53_hosted_zone_protections" {
  description = "List of AWS Shield Advanced Protections for Route53 Hosted Zones."
  value       = aws_shield_protection.shield_protection
}


provider "aws" {
  # The AWS provider to use to make changes in the DNS primary account
  alias  = "primary"
  region = var.region

  # Profile is deprecated in favor of terraform_role_arn. When profiles are not in use, terraform_profile_name is null.
  profile = module.iam_roles.dns_terraform_profile_name

  dynamic "assume_role" {
    # module.iam_roles.dns_terraform_role_arn may be null, in which case do not assume a role.
    for_each = compact([module.iam_roles.dns_terraform_role_arn])
    content {
      role_arn = assume_role.value
    }
  }
}


provider "aws" {
  region = var.region

  # Profile is deprecated in favor of terraform_role_arn. When profiles are not in use, terraform_profile_name is null.
  profile = module.iam_roles.terraform_profile_name

  dynamic "assume_role" {
    # module.iam_roles.terraform_role_arn may be null, in which case do not assume a role.
    for_each = compact([module.iam_roles.terraform_role_arn])
    content {
      role_arn = assume_role.value
    }
  }
}

module "iam_roles" {
  source  = "../account-map/modules/iam-roles"
  context = module.this.context
}


module "vpc" {
  source  = "cloudposse/stack-config/yaml//modules/remote-state"
  version = "1.5.0"

  for_each = local.private_enabled ? local.vpc_environment_names : toset([])

  component   = "vpc"
  environment = each.value

  context = module.this.context
}

module "private_ca" {
  source  = "cloudposse/stack-config/yaml//modules/remote-state"
  version = "1.5.0"

  for_each = local.private_ca_enabled && local.certificate_enabled ? [1] : []

  component   = var.certificate_authority_component_name
  stage       = var.certificate_authority_stage_name
  environment = var.certificate_authority_environment_name

  context = module.this.context
}


variable "region" {
  type        = string
  description = "AWS Region"
}

variable "zone_config" {
  description = "Zone config"
  type = list(object({
    subdomain = string
    zone_name = string
  }))
}

variable "aws_shield_protection_enabled" {
  description = "Enable or disable AWS Shield Advanced protection for Route53 Zones. If set to 'true', a subscription to AWS Shield Advanced must exist in this account."
  type        = bool
  default     = false
}

variable "dns_private_zone_enabled" {
  type        = bool
  description = "Whether to set the zone to public or private"
  default     = false
}

variable "vpc_primary_environment_name" {
  description = "The name of the environment where primary VPC is deployed"
  type        = string
  default     = null
}

variable "vpc_secondary_environment_names" {
  description = "The names of the environments where secondary VPCs are deployed"
  type        = list(string)
  default     = []
}

variable "vpc_region_abbreviation_type" {
  type        = string
  description = "Type of VPC abbreviation (either `fixed` or `short`) to use in names. See https://github.com/cloudposse/terraform-aws-utils for details."
  default     = "fixed"
  validation {
    condition     = contains(["fixed", "short"], var.vpc_region_abbreviation_type)
    error_message = "The vpc_region_abbreviation_type must be either \"fixed\" or \"short\"."
  }
}

variable "certificate_authority_enabled" {
  type        = bool
  description = "Whether to use the certificate authority or not"
  default     = false
}

variable "certificate_authority_component_name" {
  type        = string
  default     = null
  description = "Use this component name to read from the remote state to get the certificate_authority_arn if using an authority type of SUBORDINATE"
}

variable "certificate_authority_stage_name" {
  type        = string
  default     = null
  description = "Use this stage name to read from the remote state to get the certificate_authority_arn if using an authority type of SUBORDINATE"
}

variable "certificate_authority_environment_name" {
  type        = string
  default     = null
  description = "Use this environment name to read from the remote state to get the certificate_authority_arn if using an authority type of SUBORDINATE"
}

variable "certificate_authority_component_key" {
  type        = string
  default     = null
  description = "Use this component key e.g. `root` or `mgmt` to read from the remote state to get the certificate_authority_arn if using an authority type of SUBORDINATE"
}

variable "dns_soa_config" {
  type        = string
  description = <<-EOT
    Root domain name DNS SOA record:
    - awsdns-hostmaster.amazon.com. ; AWS default value for administrator email address
    - 1 ; serial number, not used by AWS
    - 7200 ; refresh time in seconds for secondary DNS servers to refresh SOA record
    - 900 ; retry time in seconds for secondary DNS servers to retry failed SOA record update
    - 1209600 ; expire time in seconds (1209600 is 2 weeks) for secondary DNS servers to remove SOA record if they cannot refresh it
    - 60 ; nxdomain TTL, or time in seconds for secondary DNS servers to cache negative responses
    See [SOA Record Documentation](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/SOA-NSrecords.html) for more information.
   EOT
  default     = "awsdns-hostmaster.amazon.com. 1 7200 900 1209600 60"
}

variable "dns_query_logging_enabled" {
  type        = bool
  default     = false
  description = "Whether to enable DNS query logging for Route53 hosted zones"
}

resource "aws_cloudwatch_log_group" "dns_logs" {
  name = "/aws/route53/query-logs"
  retention_in_days = 7
}

terraform {
  required_version = ">= 1.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 4.9.0"
    }
  }
}