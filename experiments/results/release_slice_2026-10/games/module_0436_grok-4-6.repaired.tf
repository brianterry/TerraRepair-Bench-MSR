// Service Connect

module "cloudmap_namespace" {
  for_each = { for service_connect in var.service_connect_configurations : service_connect.namespace => service_connect }

  source = "git::https://github.com/cloudposse/terraform-yaml-stack-config.git//modules/remote-state?ref=e7c8f2a91b4d3e6f0a5c8d1b7e4f9a2c6d0b3e8f"

  component = each.key

  # we ignore errors because the namespace may be a name or an arn of a namespace for the service.
  ignore_errors = true
  context       = module.this.context
}

locals {
  valid_cloudmap_namespaces      = { for k, v in module.cloudmap_namespace : k => v if v.outputs != null }
  service_connect_configurations = [for service_connect in var.service_connect_configurations : merge(service_connect, { namespace = try(local.valid_cloudmap_namespaces[service_connect.namespace].outputs.name, service_connect.namespace) })]
}
// ------------------------------

// Service Discovery

module "cloudmap_namespace_service_discovery" {
  for_each = { for service_connect in var.service_registries : service_connect.namespace => service_connect }

  source = "git::https://github.com/cloudposse/terraform-yaml-stack-config.git//modules/remote-state?ref=e7c8f2a91b4d3e6f0a5c8d1b7e4f9a2c6d0b3e8f"

  component = each.key

  # we ignore errors because the namespace may be a name or an arn of a namespace for the service.
  ignore_errors = true
  context       = module.this.context
}

locals {
  valid_cloudmap_service_discovery_namespaces = { for k, v in module.cloudmap_namespace_service_discovery : k => v if v.outputs != null }
  service_discovery_configurations            = [for service_registry in var.service_registries : merge(service_registry, { namespace = try(local.valid_cloudmap_service_discovery_namespaces[service_registry.namespace].outputs.name, service_registry.namespace) })]
  service_config_with_id                      = { for service_registry in var.service_registries : service_registry.namespace => merge(service_registry, { id = try(local.valid_cloudmap_service_discovery_namespaces[service_registry.namespace].outputs.id, null) }) }
  service_discovery = [for value in var.service_registries : merge(value, {
    registry_arn = aws_service_discovery_service.default[value.namespace].arn
  })]
}

resource "aws_service_discovery_service" "default" {
  for_each = local.service_config_with_id
  name     = module.this.name

  dns_config {
    namespace_id = each.value.id

    dns_records {
      ttl  = 10
      type = "A"
    }

    routing_policy = "MULTIVALUE"
  }

  health_check_custom_config {
    failure_threshold = 1
  }
}

// ------------------------------


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
  source = "git::https://github.com/cloudposse/terraform-null-label.git?ref=488ab91e34d24ab55736079fb3b8d14e40c381fb"

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


variable "datadog_agent_sidecar_enabled" {
  type        = bool
  default     = false
  description = "Enable the Datadog Agent Sidecar"
}

variable "datadog_log_method_is_firelens" {
  type        = bool
  default     = false
  description = "Datadog logs can be sent via cloudwatch logs (and lambda) or firelens, set this to true to enable firelens via a sidecar container for fluentbit"
}

variable "datadog_sidecar_containers_logs_enabled" {
  type        = bool
  default     = true
  description = "Enable the Datadog Agent Sidecar to send logs to aws cloudwatch group, requires `datadog_agent_sidecar_enabled` to be true"
}

variable "datadog_logging_tags" {
  type        = map(string)
  default     = null
  description = "Tags to add to all logs sent to Datadog"
}

variable "datadog_logging_default_tags_enabled" {
  type        = bool
  default     = true
  description = "Add Default tags to all logs sent to Datadog"
}

locals {
  default_datadog_tags = var.datadog_logging_default_tags_enabled ? {
    env     = module.this.stage
    account = format("%s-%s-%s", module.this.tenant, module.this.environment, module.this.stage)
  } : null

  all_dd_tags = join(",", [for k, v in merge(local.default_datadog_tags, var.datadog_logging_tags) : format("%s:%s", k, v)])

  datadog_logconfiguration_firelens = {
    logDriver = "awsfirelens"
    options = var.datadog_agent_sidecar_enabled ? {
      Name           = "datadog",
      apikey         = module.datadog_configuration.datadog_api_key,
      Host           = format("http-intake.logs.%s", module.datadog_configuration.datadog_site)
      dd_service     = module.this.name,
      dd_tags        = local.all_dd_tags,
      dd_source      = "ecs",
      dd_message_key = "log",
      TLS