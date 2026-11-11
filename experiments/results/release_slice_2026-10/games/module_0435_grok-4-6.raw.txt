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
  source = "git::https://github.com/cloudposse/terraform-null-label.git?ref=488ab606e1c4331d1d79f6b174a5aa14cc9208a4"

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

  dns_enabled = local.enabled && var.route53_enabled

  # If var.acm_certificate_domain is defined, use it.
  # Else if var.acm_certificate_domain_suffix is defined, use {{ var.acm_certificate_domain_suffix }}.{{ environment }}.{{ domain }}
  # Else, use {{ environment }}.{{ domain }}
  acm_certificate_domain = try(length(var.acm_certificate_domain) > 0, false) ? var.acm_certificate_domain : try(length(var.acm_certificate_domain_suffix) > 0, false) ? format("%s.%s.%s", var.acm_certificate_domain_suffix, var.environment, module.dns_delegated.outputs.default_domain_name) : format("%s.%s", var.environment, module.dns_delegated.outputs.default_domain_name)

  maintenance_page_fixed_response = {
    content_type = "text/html"
    status_code  = "503"
    message_body = file("${path.module}/${var.maintenance_page_path}")
  }
}

# This is used due to the short limit on target group names i.e. 32 characters
module "target_group_label" {
  source = "git::https://github.com/cloudposse/terraform-null-label.git?ref=488ab606e1c4331d1d79f6b174a5aa14cc9208a4"

  name = "default"

  tenant      = ""
  namespace   = ""
  stage       = ""
  environment = ""

  context = module.this.context
}

resource "aws_security_group" "default" {
  count       = local.enabled ? 1 : 0
  name        = module.this.id
  description = "ECS cluster EC2 autoscale capacity providers"
  vpc_id      = module.vpc.outputs.vpc_id
}

resource "aws_security_group_rule" "ingress_cidr" {
  for_each          = local.enabled ? toset(var.allowed_cidr_blocks) : []
  type              = "ingress"
  from_port         = 0
  to_port           = 65535
  protocol          = "tcp"
  cidr_blocks       = [each.value]
  security_group_id = join("", aws_security_group.default[*].id)
  description       = "Allow inbound TCP from allowed CIDR blocks to ECS cluster capacity providers"
}

resource "aws_security_group_rule" "ingress_security_groups" {
  for_each                 = local.enabled ? toset(var.allowed_security_groups) : []
  type                     = "ingress"
  from_port                = 0
  to_port                  = 65535
  protocol                 = "tcp"
  source_security_group_id = each.value
  security_group_id        = join("", aws_security_group.default[*].id)
  description              = "Allow inbound TCP from allowed security groups to ECS cluster capacity providers"
}

resource "aws_security_group_rule" "egress" {
  count             = local.enabled ? 1 : 0
  type              = "egress"
  from_port         = 0
  to_port           = 65535
  protocol          = "tcp"
  cidr_blocks       = [module.vpc.outputs.vpc_cidr]
  security_group_id = join("", aws_security_group.default[*].id)
  description       = "Allow outbound TCP from ECS cluster capacity providers to the VPC"
}

module "cluster" {
  source = "git::https://github.com/cloudposse/terraform-aws-ecs-cluster.git?ref=e8c4a2f1b7d39506c4e8a1b2d7f0c3e5a9b6d4f2"

  context = module.this.context

  container_insights_enabled      = var.container_insights_enabled
  capacity_providers_fargate      = var.capacity_providers_fargate
  capacity_providers_fargate_spot = var.capacity_providers_fargate_spot
  capacity_providers_ec2 = {
    for name, provider in var.capacity_providers_ec2 :
    name => merge(
      provider,
      {
        security_group_ids          = concat(aws_security_group.default[*].id, provider.security_group_ids)
        subnet_ids                  = var.internal_enabled ? module.vpc.outputs.private_subnet_ids : module.vpc.outputs.public_subnet_ids
        associate_public_ip_address = !var.internal_enabled
      }
    )
  }

  #  external_ec2_capacity_providers = {
  #    external_default = {
  #      autoscaling_group_arn          = module.autoscale_group.autoscaling_group_arn
  #      managed_termination_protection = false
  #      managed_scaling_status         = false
  #      instance_warmup_period         = 300
  #      maximum_scaling_step_size      = 1
  #      minimum_scaling_step_size      = 1
  #      target_capacity_utilization    = 100
  #    }
  #  }

}

#locals {
#  user_data = <<EOT
##!/bin/bash
#echo ECS_CLUSTER="${module.cluster.name}" >> /etc/ecs/ecs.config
#echo ECS_ENABLE_CONTAINER_METADATA=true >> /etc/ecs/ecs.config
#echo ECS_POLL_METRICS=true >> /etc/ecs/ecs.config
#EOT
#
#}
#
#data "aws_ssm_parameter" "ami" {
#  name = "/aws/service/ecs/optimized-ami/amazon-linux-2/recommended/image_id"
#}
#
#module "autoscale_group" {
#  source  = "cloudposse/ec2-autoscale-group/aws"
#  version = "0.31.1"
#
#  context = module.this.context
#
#  image_id                    = data.aws_ssm_parameter.ami.value
#  instance_type               = "t3.medium"
#  security_group_ids          = aws_security_group.default[*].id
#  subnet_ids                  = var.internal_enabled ? module.vpc.outputs.private_subnet_ids : module.vpc.outputs.public_subnet_ids
#  health_check_type           = "EC2"
#  desired_capacity            = 1
#  min_size                    = 1
#  max_size                    = 2
#  wait_for_capacity_timeout   = "5m"
#  associate_public_ip_address = true
#  user_data_base64            = base64encode(local.user_data)
#
#  # Auto-scaling policies and CloudWatch metric alarms
#  autoscaling_policies_enabled           = true
#  cpu_utilization_high_threshold_percent = "70"
#  cpu_utilization_low_threshold_percent  = "20"
#
#  iam_instance_profile_name = module.cluster.role_name
#}


resource "aws_route53_record" "default" {
  for_each = local.dns_enabled ? var.alb_configuration : {}
  zone_id  = module.dns_delegated.outputs.default_dns_zone_id
  name     = format("%s.%s", lookup(each.value, "route53_record_name", var.route53_record_name), var.environment)
  type     = "A"

  alias {
    name                   = module.alb[each.key].alb_dns_name
    zone_id                = module.alb[each.key].alb_zone_id
    evaluate_target_health = true
  }
}

data "aws_acm_certificate" "default" {
  count       = local.enabled ? 1 : 0
  domain      = local.acm_certificate_domain
  statuses    = ["ISSUED"]
  most_recent = true
}

module "alb" {
  source = "git::https://github.com/cloudposse/terraform-aws-alb.git?ref=b5d9e3a7c1f4e8b2d6a0c4f8e2b6d0a4c8f2e6b0"

  for_each = local.enabled ? var.alb_configuration : {}

  vpc_id          = module.vpc.outputs.vpc_id
  subnet_ids      = lookup(each.value, "internal_enabled", var.internal_enabled) ? module.vpc.outputs.private_subnet_ids : module.vpc.outputs.public_subnet_ids
  ip_address_type = lookup(each.value, "ip_address_type", "ipv4")

  internal = lookup(each.value, "internal_enabled", var.internal_enabled)

  security_group_enabled = lookup(each.value