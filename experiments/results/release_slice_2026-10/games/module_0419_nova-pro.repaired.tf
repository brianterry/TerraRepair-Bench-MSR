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

locals {
  enabled = module.this.enabled

  sub_domain = var.name
  root_domain = coalesce(module.acm.outputs.domain_name, join(".", [
    module.this.environment, module.dns_delegated.outputs.default_domain_name
  ]), module.dns_delegated.outputs.default_domain_name)
  domain_name = join(".", [local.sub_domain, local.root_domain])
}

module "api_gateway_rest_api" {
  source  = "cloudposse/api-gateway/aws"
  version = "0.3.1"

  enabled = local.enabled

  openapi_config           = var.openapi_config
  endpoint_type            = var.endpoint_type
  logging_level            = var.logging_level
  metrics_enabled          = var.metrics_enabled
  xray_tracing_enabled     = var.xray_tracing_enabled
  access_log_format        = var.access_log_format
  rest_api_policy          = var.rest_api_policy
  private_link_target_arns = module.nlb[*].nlb_arn

  context = module.this.context
}

data "aws_acm_certificate" "issued" {
  count    = local.enabled? 1 : 0
  domain   = local.root_domain
  statuses = ["ISSUED"]
}

data "aws_route53_zone" "this" {
  count        = local.enabled? 1 : 0
  name         = module.dns_delegated.outputs.default_domain_name
  private_zone = false
}

resource "aws_api_gateway_domain_name" "this" {
  count                    = local.enabled? 1 : 0
  domain_name              = local.domain_name
  regional_certificate_arn = data.aws_acm_certificate.issued[0].arn
  security_policy          = "TLS_1_2"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = module.this.tags
}

resource "aws_api_gateway_base_path_mapping" "this" {
  count       = local.enabled? 1 : 0
  api_id      = module.api_gateway_rest_api.id
  domain_name = aws_api_gateway_domain_name.this[0].domain_name
  stage_name  = module.this.stage

  depends_on = [
    aws_api_gateway_domain_name.this,
    module.api_gateway_rest_api
  ]

}

resource "aws_route53_record" "this" {
  count   = local.enabled? 1 : 0
  name    = aws_api_gateway_domain_name.this[0].domain_name
  type    = "A"
  zone_id = data.aws_route53_zone.this[0].id

  alias {
    evaluate_target_health = true
    name                   = aws_api_gateway_domain_name.this[0].regional_domain_name
    zone_id                = aws_api_gateway_domain_name.this[0].regional_zone_id
  }
}

module "nlb" {
  source  = "cloudposse/nlb/aws"
  version = "0.12.0"
  count   = var.enable_private_link_nlb? 1 : 0

  enabled = local.enabled

  vpc_id                                  = module.vpc.outputs.vpc.id
  subnet_ids                              = module.vpc.outputs.private_subnet_ids
  internal                                = true
  tcp_enabled                             = true
  cross_zone_load_balancing_enabled       = true
  ip_address_type                         = "ipv4"
  deletion_protection_enabled             = var.enable_private_link_nlb_deletion_protection
  tcp_port                                = 443
  target_group_port                       = 443
  target_group_target_type                = "alb"
  health_check_protocol                   = "HTTPS"
  nlb_access_logs_s3_bucket_force_destroy = true
  deregistration_delay                    = var.deregistration_delay

  context = module.this.context
}

module "dns_delegated" {
  source  = "cloudposse/stack-config/yaml//modules/remote-state"
  version = "1.5.0"

  component   = "dns-delegated"
  environment = module.iam_roles.global_environment_name

  context = module.this.context
}

module "acm" {
  source  = "cloudposse/stack-config/yaml//modules/remote-state"
  version = "1.5.0"

  component     = "acm"
  ignore_errors = true

  defaults = {
    domain_name = ""
  }

  context = module.this.context
}

module "vpc" {
  source  = "cloudposse/stack-config/yaml//modules/remote-state"
  version = "1.5.0"

  component = "vpc"

  context = module.this.context
}

provider "aws" {
  region = var.region

  profile = module.iam_roles.terraform_profile_name

  dynamic "assume_role" {
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
    condition     = lookup(var.context, "label_key_case", null) == null? true : contains(["lower", "title", "upper"], var.context["label_key_case"])
    error_message = "Allowed values: `lower`, `title`, `upper`."
  }

  validation {
    condition     = lookup(var.context, "label_value_case", null) == null? true : contains(["lower", "title", "upper", "none"], var.context["label_value_case"])
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
    condition     = var.id_length_limit == null? true : var.id_length_limit >= 6 || var.id_length_limit == 0
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
    condition     = var.label_key_case == null? true : contains(["lower", "title", "upper"], var.label_key_case)
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
    condition     = var.label_value_case == null? true : contains(["lower", "title", "upper", "none"], var.label_value_case)
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

variable "region" {
  type        = string
  description = "AWS Region"
}

variable "openapi_config" {
  description = "The OpenAPI specification for the API"
  type        = any
  default     = {}
}

variable "endpoint_type" {
  type        = string
  description = "The type of the endpoint. One of - PUBLIC, PRIVATE, REGIONAL"
  default     = "REGIONAL"

  validation {
    condition     = contains(["EDGE", "REGIONAL", "PRIVATE"], var.endpoint_type)
    error_message = "Valid values for var: endpoint_type are (EDGE, REGIONAL, PRIVATE)."
  }
}

variable "logging_level" {
  type        = string
  description = "The logging level of the API. One of - OFF, INFO, ERROR"
  default     = "INFO"

  validation {
    condition     = contains(["OFF", "INFO", "ERROR"], var.logging_level)
    error_message = "Valid values for var: logging_level are (OFF, INFO, ERROR)."
  }
}

variable "metrics_enabled" {
  description = "A flag to indicate whether to enable metrics collection."
  type        = bool
  default     = true
}

variable "xray_tracing_enabled" {
  description = "A flag to indicate whether to enable X-Ray tracing."
  type        = bool
  default     = true
}

variable "access_log_format" {
  description = "The format of the access log file."
  type        = string
  default     = <<EOF
  {
  "requestTime": "$context.requestTime",
  "requestId": "$context.requestId",
  "httpMethod": "$context.httpMethod",
  "path": "$context.path",
  "resourcePath": "$context.resourcePath",
  "status": $context.status,
  "responseLatency": $context.responseLatency,
  "xrayTraceId": "$context.xrayTraceId",
  "integrationRequestId": "$context.integration.requestId",
  "functionResponseStatus": "$context.integration.status",
  "integrationLatency": "$context.integration.latency",
  "integrationServiceStatus": "$context.integration.integrationStatus",
  "authorizeResultStatus": "$context.authorize.status",
  "authorizerServiceStatus": "$context.authorizer.status",
  "authorizerLatency": "$context.authorizer.latency",
  "authorizerRequestId": "$context.authorizer.requestId",
  "ip": "$context.identity.sourceIp",
  "userAgent": "$context.identity.userAgent",
  "principalId": "$context.authorizer.principalId",
  "cognitoUser": "$context.identity.cognitoIdentityId",
  "user": "$context.identity.user"
}
  EOF
}

variable "rest_api_policy" {
  description = "The IAM policy document for the API."
  type        = string
  default     = null
}

variable "fully_qualified_domain_name" {
  description = "The fully qualified domain name of the API."
  type        = string
  default     = null
}

variable "enable_private_link_nlb_deletion_protection" {
  description = "A flag to indicate whether to enable private link deletion protection."
  type        = bool
  default     = false
}

variable "deregistration_delay" {
  type        = number
  default     = 15
  description = "The amount of time to wait in seconds before changing the state of a deregistering target to unused"
}

variable "enable_private_link_nlb" {
  description = "A flag to indicate whether to enable private link."
  type        = bool
  default     = false
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