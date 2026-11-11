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

locals {
  failover_enabled = local.enabled && try(length(var.failover_s3_origin_environment), 0) > 0
  failover_region  = local.failover_enabled ? module.utils.region_az_alt_code_maps.from_fixed[var.failover_s3_origin_environment] : var.region
  failover_bucket  = local.failover_enabled ? format(var.failover_s3_origin_format, var.namespace, var.failover_s3_origin_environment, var.stage, var.name) : null
}

module "utils" {
  source  = "cloudposse/utils/aws"
  version = "1.3.0"
}

data "aws_s3_bucket" "failover_bucket" {
  count = local.failover_enabled ? 1 : 0

  bucket = local.failover_bucket

  provider = aws.failover
}


locals {
  github_actions_iam_policy = data.aws_iam_policy_document.github_actions_iam_policy.json
}

data "aws_iam_policy_document" "github_actions_iam_policy" {
  statement {
    sid    = "BucketActions"
    effect = "Allow"
    actions = [
      "s3:ListBucket",
      "s3:ListBucketMultipartUploads",
      "s3:AbortMultipartUpload"
    ]
    resources = [module.spa_web.s3_bucket_arn]
  }

  statement {
    sid    = "ObjectActions"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:DeleteObject",
      "s3:PutObject",
      "s3:PutObjectTagging",
      "s3:PutObjectAcl"
    ]
    resources = [format("%s/*", module.spa_web.s3_bucket_arn)]
  }

  statement {
    sid    = "CloudfrontActions"
    effect = "Allow"
    actions = [
      "cloudfront:CreateInvalidation"
    ]
    resources = [
      module.spa_web.cf_arn
    ]
  }
}


variable "github_actions_iam_role_enabled" {
  type        = bool
  description = <<-EOF
  Flag to toggle creation of an IAM Role that GitHub Actions can assume to access AWS resources
  EOF
  default     = false
}

variable "github_actions_allowed_repos" {
  type        = list(string)
  description = <<EOF
  A list of the GitHub repositories that are allowed to assume this role from GitHub Actions. For example,
  ["cloudposse/infra-live"]. Can contain "*" as wildcard.
  If org part of repo name is omitted, "cloudposse" will be assumed.
  EOF
  default     = []
}

variable "github_actions_iam_role_attributes" {
  type        = list(string)
  description = "Additional attributes to add to the role name"
  default     = []
}


locals {
  github_actions_iam_role_enabled = local.enabled && var.github_actions_iam_role_enabled && length(var.github_actions_allowed_repos) > 0
}

module "gha_role_name" {
  source  = "cloudposse/label/null"
  version = "0.25.0"

  enabled    = local.github_actions_iam_role_enabled
  attributes = compact(concat(var.github_actions_iam_role_attributes, ["gha"]))

  context = module.this.context
}

module "gha_assume_role" {
  source = "../account-map/modules/team-assume-role-policy"

  trusted_github_repos = var.github_actions_allowed_repos

  context = module.gha_role_name.context
}

resource "aws_iam_role" "github_actions" {
  count              = local.github_actions_iam_role_enabled ? 1 : 0
  name               = module.gha_role_name.id
  assume_role_policy = module.gha_assume_role.github_assume_role_policy

  inline_policy {
    name   = module.gha_role_name.id
    policy = local.github_actions_iam_policy
  }
}

output "github_actions_iam_role_arn" {
  value       = one(aws_iam_role.github_actions[*].arn)
  description = "ARN of IAM role for GitHub Actions"
}

output "github_actions_iam_role_name" {
  value       = one(aws_iam_role.github_actions[*].name)
  description = "Name of IAM role for GitHub Actions"
}


locals {
  cloudfront_lambda_function_association = concat(var.cloudfront_lambda_function_association, module.lambda_edge.lambda_function_association)
}

moved {
  from = module.lambda-edge-preview.module.lambda_edge.aws_lambda_function.default["origin_request"]
  to   = module.lambda_edge.aws_lambda_function.default["origin_request"]
}
moved {
  from = module.lambda_edge_redirect_404.module.lambda_edge.aws_lambda_function.default["origin_response"]
  to   = module.lambda_edge.aws_lambda_function.default["origin_response"]
}
moved {
  from = module.lambda_edge_redirect_404.module.lambda_edge.aws_lambda_function.default["viewer_request"]
  to   = module.lambda_edge.aws_lambda_function.default["viewer_request"]
}

module "lambda_edge_functions" {
  source  = "cloudposse/config/yaml//modules/deepmerge"
  version = "1.0.2"

  count = local.enabled ? 1 : 0

  maps = [
    local.preview_environment_enabled ? {
      origin_request = {
        source = [{
          content  = <<-EOT
          exports.handler = (event, context, callback) => {
              const site_fqdn = "${local.site_fqdn}";

              const { request } = event.Records[0].cf;
              const default_prefix = "";

              console.log('request:' + JSON.stringify(request));

              let host = null;

              if (request.headers.hasOwnProperty('x-forwarded-host')) {
                host = request.headers['x-forwarded-host'][0].value;
              } else {
                host = site_fqdn;
              }
              if (host == site_fqdn) {
                request.origin.custom.path = default_prefix; // use default prefix if there is no subdomain
              } else {
                const subdomain = host.replace('.' + site_fqdn, '');
                request.origin.custom.path = `/$${subdomain}`; // use preview prefix
              }

              return callback(null, request);
          };
          EOT
          filename = "index.js"
        }]
        runtime      = var.lambda_edge_runtime
        handler      = var.lambda_edge_handler
        event_type   = "origin-request"
        include_body = false
      },
      viewer_request = {
        source = [{
          content  = <<-EOT
          exports.handler = (event, context, callback) => {
            const { request } = event.Records[0].cf;
            if ('host' in request.headers) {
              request.headers['x-forwarded-host'] = [
                {
                  key: 'X-Forwarded-Host',
                  value: request.headers.host[0].value
                }
              ];
            }
            return callback(null, request);
          };
          EOT
          filename = "index.js"
        }]
        runtime      = var.lambda_edge_runtime
        handler      = var.lambda_edge_handler
        event_type   = "viewer-request"
        include_body = false
      }
    } : {},
    var.lambda_edge_functions,
  ]
}

module "lambda_edge" {
  source  = "cloudposse/cloudfront-s3-cdn/aws//modules/lambda@edge"
  version = "0.92.0"

  functions         = jsondecode(local.enabled ? jsonencode(module.lambda_edge_functions[0].merged) : jsonencode({}))
  destruction_delay = var.lambda_edge_destruction_delay

  providers = {
    aws = aws.us-east-1
  }

  context = module.this.context
}

data "aws_iam_policy_document" "additional_lambda_edge_permission" {
  count = local.enabled && (length(var.lambda_edge_allowed_ssm_parameters) > 0) ? 1 : 0
  statement {
    effect    = "Allow"
    actions   = ["ssm:GetParameter*"]
    resources = var.lambda_edge_allowed_ssm_parameters
  }
}

resource "aws_iam_policy" "additional_lambda_edge_permission" {
  count = local.enabled && (length(var.lambda_edge_allowed_ssm_parameters) > 0) ? 1 : 0

  name   = "${module.this.id}-read-ssm-vars"
  policy = data.aws_iam_policy_document.additional_lambda_edge_permission[0].json
}

resource "aws_iam_role_policy_attachment" "additional_lambda_edge_permission" {
  for_each = local.enabled && (length(var.lambda_edge_allowed_ssm_parameters) > 0) ? toset(keys(module.lambda_edge_functions[0].merged)) : toset([])

  policy_arn = aws_iam_policy.additional_lambda_edge_permission[0].arn
  role       = split("/", module.lambda_edge.lambda_functions[each.key].role_arn)[1]
}


locals {
  enabled                           = module.this.enabled
  aws_shield_enabled                = local.enabled && var.cloudfront_aws_shield_protection_enabled
  aws_waf_enabled                   = local.enabled && var.cloudfront_aws_waf_protection_enabled
  github_runners_enabled            = local.enabled && var.github_runners_deployment_principal_arn_enabled
  parent_zone_name                  = length(var.parent_zone_name) > 0 ? var.parent_zone_name : try(module.dns_delegated.outputs.default_domain_name, null)
  site_fqdn                         = length(var.site_fqdn) > 0 ? var.site_fqdn : format("%v.%v.%v", var.site_subdomain, module.this.environment, local.parent_zone_name)
  s3_access_log_bucket_name         = var.origin_s3_access_log_bucket_name_rendering_enabled ? format("%[1]v-${module.this.tenant != null ? "%[2]v-" : ""}%[3]v-%[4]v-%[5]v", var.namespace, var.tenant, var.environment, var.stage, var.origin_s3_access_log_bucket_name) : var.origin_s3_access_log_bucket_name
  cloudfront_access_log_bucket_name = var.cloudfront_access_log_bucket_name_rendering_enabled ? format("%[1]v-${module.this.tenant != null ? "%[2]v-" : ""}%[3]v-%[4]v-%[5]v", var.namespace, var.tenant, var.environment, var.stage, var.cloudfront_access_log_bucket_name) : var.cloudfront_access_log_bucket_name
  cloudfront_access_log_prefix      = var.cloudfront_access_log_prefix_rendering_enabled ? "${var.cloudfront_access_log_prefix}${module.this.id}" : var.cloudfront_access_log_prefix
  origin_deployment_principal_arns  = local.github_runners_enabled ? concat(var.origin_deployment_principal_arns, [module.github_runners.outputs.iam_role_arn]) : var.origin_deployment_principal_arns

  preview_environment_enabled         = local.enabled && var.preview_environment_enabled
  preview_environment_wildcard_domain = format("%v.%v", "*", local.site_fqdn)
  aliases                             = concat([local.site_fqdn], local.preview_environment_enabled ? [local.preview_environment_wildcard_domain] : [])
  external_aliases                    = local.preview_environment_enabled ? [] : var.external_aliases
  subject_alternative_names           = local.preview_environment_enabled ? [local.preview_environment_wildcard_domain] : var.external_aliases
  s3_website_enabled                  = var.s3_website_enabled || local.preview_environment_enabled
  s3_website_password_enabled         = var.s3_website_password_enabled || local.preview_environment_enabled
  s3_object_ownership                 = local.preview_environment_enabled ? "BucketOwnerEnforced" : var.s3_object_ownership
  s3_failover_origin = local.failover_enabled ? [{
    domain_name = data.aws_s3_bucket.failover_bucket[0].bucket_domain_name
    origin_id   = data.aws_s3_bucket.failover_bucket[0].bucket
    origin_path = null
    s3_origin_config = {
      origin_access_identity = null
    }
  }] : []
  s3_origins                         = local.enabled ? concat(local.s3_failover_origin, var.s3_origins) : []
  block_origin_public_access_enabled = var.block_origin_public_access_enabled && !local.preview_environment_enabled

  origin_allow_ssl_requests_only = var.origin_allow_ssl_requests_only && !local.s3_website_enabled

  forward_header_values  = local.preview_environment_enabled ? concat(var.forward_header_values, ["x-forwarded-host"]) : var.forward_header_values
  cloudfront_default_ttl = local.preview_environment_enabled ? 0 : var.cloudfront_default_ttl
  cloudfront_min_ttl     = local.preview_environment_enabled ? 0 : var.cloudfront_min_ttl
  cloudfront_max_ttl     = local.preview_environment_enabled ? 0 : var.cloudfront_max_ttl
}

module "acm_request_certificate" {
  source  = "cloudposse/acm-request-certificate/aws"
  version = "0.18.0"
  providers = {
    aws = aws.us-east-1
  }

  domain_name                       = local.site_fqdn
  subject_alternative_names         = local.subject_alternative_names
  zone_name                         = local.parent_zone_name
  process_domain_validation_options = var.process_domain_validation_options
  ttl                               = 300

  context = module.this.context
}

module "spa_web" {
  source  = "cloudposse/cloudfront-s3-cdn/aws"
  version = "0.95.0"

  block_origin_public_access_enabled = local.block_origin_public_access_enabled
  encryption_enabled                 = var.origin_encryption_enabled
  origin_force_destroy               = var.origin_force_destroy
  versioning_enabled                 = var.origin_versioning_enabled
  web_acl_id                         = local.aws_waf_enabled ? module.waf.outputs.acl.arn : null

  cloudfront_access_log_create_bucket = var.cloudfront_access_log_create_bucket
  cloudfront_access_log_bucket_name   = local.cloudfront_access_log_bucket_name
  cloudfront_access_log_prefix        = local.cloudfront_access_log_prefix

  index_document      = var.cloudfront_index_document
  default_root_object = var.cloudfront_default_root_object

  s3_access_logging_enabled = var.origin_s3_access_logging_enabled
  s3_access_log_bucket_name = local.s3_access_log_bucket_name
  s3_access_log_prefix      = var.origin_s3_access_log_prefix

  comment                     = var.comment
  aliases                     = local.aliases
  external_aliases            = local.external_aliases
  parent_zone_name            = local.parent_zone_name
  dns_alias_enabled           = true
  website_enabled             = local.s3_website_enabled
  s3_website_password_enabled = local.s3_website_password_enabled
  allow_ssl_requests_only     = local.origin_allow_ssl_requests_only
  acm_certificate_arn         = module.acm_request_certificate.arn
  ipv6_enabled                = var.cloudfront_ipv6_enabled

  http_version          = var.http_version
  allowed_methods       = var.cloudfront_allowed_methods
  cached_methods        = var.cloudfront_cached_methods
  custom_error_response = var.cloudfront_custom_error_response
  default_ttl           = local.cloudfront_default_ttl
  min_ttl               = local.cloudfront_min_ttl
  max_ttl               = local.cloudfront_max_ttl

  ordered_cache         = local.ordered_cache
  forward_cookies       = var.forward_cookies
  forward_header_values = local.forward_header_values

  compress               = var.cloudfront_compress
  viewer_protocol_policy = var.cloudfront_viewer_protocol_policy

  deployment_principal_arns = { for arn in local.origin_deployment_principal_arns : arn => [""] }
  deployment_actions = var.origin_deployment_actions

  lambda_function_association = local.cloudfront_lambda_function_association

  custom_origins = var.custom_origins
  origin_bucket  = var.origin_bucket
  origin_groups = local.failover_enabled ? [{
    primary_origin_id  = null
    failover_origin_id = data.aws_s3_bucket.failover_bucket[0].bucket
    failover_criteria  = var.failover_criteria_status_codes
  }] : []

  s3_object_ownership = local.s3_object_ownership
  s3_origins          = local.s3_origins

  context = module.this.context
}

resource "aws_shield_protection" "shield_protection" {
  count = local.aws_shield_enabled ? 1 : 0

  name         = module.spa_web.cf_id
  resource_arn = module.spa_web.cf_arn
}


resource "aws_cloudfront_cache_policy" "created_cache_policies" {
  for_each = {
    for cache in var.ordered_cache : cache.cache_policy_name => cache if cache.cache_policy_id == null
  }

  comment     = var.comment
  default_ttl = each.value.default_ttl
  max_ttl     = each.value.max_ttl
  min_ttl     = each.value.min_ttl
  name        = each.value.cache_policy_name
  parameters_in_cache_key_and_forwarded_to_origin {
    cookies_config {
      cookie_behavior = "none"
    }
    headers_config {
      header_behavior = "none"
    }
    query_strings_config {
      query_string_behavior = "none"
    }
  }
}

resource "aws_cloudfront_origin_request_policy" "created_origin_request_policies" {
  for_each = {
    for cache in var.ordered_cache : cache.origin_request_policy_name => cache if cache.origin_request_policy_id == null
  }

  comment = var.comment
  name    = each.value.origin_request_policy_name
  cookies_config {
    cookie_behavior = each.value.origin_request_policy.cookie_behavior
    dynamic "cookies" {
      for_each = length(each.value.origin_request_policy.cookies) > 0 ? [each.value.origin_request_policy.cookies] : []
      content {
        items = cookies.value
      }
    }
  }
  headers_config {
    header_behavior = each.value.origin_request_policy.header_behavior
    dynamic "headers" {
      for_each = length(each.value.origin_request_policy.headers) > 0 ? [each.value.origin_request_policy.headers] : []
      content {
        items = headers.value
      }
    }
  }
  query_strings_config {
    query_string_behavior = each.value.origin_request_policy.query_string_behavior
    dynamic "query_strings" {
      for_each = length(each.value.origin_request_policy.query_strings) > 0 ? [each.value.origin_request_policy.query_strings] : []
      content {
        items = query_strings.value
      }
    }
  }
}

locals {
  ordered_cache = [
    for cache in var.ordered_cache : merge(cache, {
      cache_policy_id          = cache.cache_policy_id == null ? aws_cloudfront_cache_policy.created_cache_policies[cache.cache_policy_name].id : cache.cache_policy_id
      origin_request_policy_id = cache.origin_request_policy_id == null ? aws_cloudfront_origin_request_policy.created_origin_request_policies[cache.origin_request_policy_name].id : cache.origin_request_policy_id
    })
  ]
}


output "origin_s3_bucket_name" {
  value       = module.spa_web.s3_bucket
  description = "Origin bucket name."
}

output "origin_s3_bucket_arn" {
  value       = module.spa_web.s3_bucket_arn
  description = "Origin bucket ARN."
}

output "cloudfront_distribution_domain_name" {
  value       = module.spa_web.cf_domain_name
  description = "Cloudfront Distribution Domain Name."
}

output "cloudfront_distribution_alias" {
  value       = module.spa_web.aliases
  description = "Cloudfront Distribution Alias Record."
}

output "cloudfront_distribution_identity_arn" {
  value       = module.spa_web.cf_identity_iam_arn
  description = "CloudFront Distribution Origin Access Identity IAM ARN."
}

output "failover_s3_bucket_name" {
  value       = try(data.aws_s3_bucket.failover_bucket[0].bucket, null)
  description = "Failover Origin bucket name, if enabled."
}


provider "aws" {
  region = local.failover_region

  alias = "failover"

  profile = module.iam_roles.terraform_profile_name

  dynamic "assume_role" {
    for_each = compact([module.iam_roles.terraform_role_arn])
    content {
      role_arn = assume_role.value
    }
  }
}

provider "aws" {
  region = "us-east-1"

  alias = "us-east-1"

  profile = module.iam_roles.terraform_profile_name

  dynamic "assume_role" {
    for_each = compact([module.iam_roles.terraform_role_arn])
    content {
      role_arn = assume_role.value
    }
  }
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


module "waf" {
  source  = "cloudposse/stack-config/yaml//modules/remote-state"
  version = "1.5.0"

  bypass      = !local.aws_waf_enabled
  component   = var.cloudfront_aws_waf_component_name
  privileged  = false
  environment = var.cloudfront_aws_waf_environment

  defaults = {
    acl = {
      arn = ""
    }
  }

  context = module.this.context
}

module "dns_delegated" {
  source  = "cloudposse/stack-config/yaml//modules/remote-state"
  version = "1.5.0"

  component   = "dns-delegated"
  environment = var.dns_delegated_environment_name

  context = module.this.context
}

module "github_runners" {
  source  = "cloudposse/stack-config/yaml//modules/remote-state"
  version = "1.5.0"

  bypass      = !local.github_runners_enabled
  component   = var.github_runners_component_name
  stage       = var.github_runners_stage_name
  environment = var.github_runners_environment_name
  tenant      = try(var.github_runners_tenant_name, module.this.tenant)

  context = module.this.context
}


variable "region" {
  type        = string
  description = "AWS Region."
}

variable "parent_zone_name" {
  type        = string
  default     = ""
  description = "Parent domain name of site to publish. Defaults to format(parent_zone_name_pattern, stage, environment)."
}

variable "process_domain_validation_options" {
  type        = bool
  default     = true
  description = "Flag to enable/disable processing of the record to add to the DNS zone to complete certificate validation"
}

variable "site_fqdn" {
  type        = string
  default     = ""
  description = "Fully qualified domain name of site to publish. Overrides site_subdomain and parent_zone_name."
}

variable "site_subdomain" {
  type        = string
  default     = ""
  description = "Subdomain to plug into site_name_pattern to make site FQDN."
}

variable "external_aliases" {
  type        = list(string)
  default     = []
  description = <<-EOT
    List of FQDN's - Used to set the Alternate Domain Names (CNAMEs) setting on CloudFront. No new Route53 records will be created for these.

    Setting `process_domain_validation_options` to true may cause the component to fail if an external_alias DNS zone is not controlled by Terraform.

    Setting `preview_environment_enabled` to `true` will cause this variable to be ignored.
    EOT
}

variable "s3_website_enabled" {
  type        = bool
  default     = false
  description = <<-EOT
    Set to true to enable the created S3 bucket to serve as a website independently of CloudFront,
    and to use that website as the origin.

    Setting `preview_environment_enabled` will implicitly set this to `true`.
    EOT
}

variable "s3_website_password_enabled" {
  type        = bool
  default     = false
  description = <<-EOT
    If set to true, and `s3_website_enabled` is also true, a password will be required in the `Referrer` field of the
    HTTP request in order to access the website, and CloudFront will be configured to pass this password in its requests.
    This will make it much harder for people to bypass CloudFront and access the S3 website directly via its website endpoint.
    EOT
}

variable "s3_object_ownership" {
  type        = string
  default     = "ObjectWriter"
  description = "Specifies the S3 object ownership control on the origin bucket. Valid values are `ObjectWriter`, `BucketOwnerPreferred`, and 'BucketOwnerEnforced'."
}

variable "s3_origins" {
  type = list(object({
    domain_name = string
    origin_id   = string
    origin_path = string
    s3_origin_config = object({
      origin_access_identity = string
    })
  }))
  default     = []
  description = <<-EOT
    A list of S3 [origins](https://www.terraform.io/docs/providers/aws/r/cloudfront_distribution.html#origin-arguments) (in addition to the one created by this component) for this distribution.
    S3 buckets configured as websites are `custom_origins`, not `s3_origins`.
    Specifying `s3_origin_config.origin_access_identity` as `null` or `""` will have it translated to the `origin_access_identity` used by the origin created by this component.
    EOT
}

variable "origin_bucket" {
  type        = string
  default     = null
  description = "Name of an existing S3 bucket to use as the origin. If this is not provided, this component will create a new s3 bucket using `var.name` and other context related inputs"
}

variable "origin_s3_access_logging_enabled" {
  type        = bool
  default     = null
  description = <<-EOF
    Set `true` to deliver S3 Access Logs to the `origin_s3_access_log_bucket_name` bucket.
    Defaults to `false` if `origin_s3_access_log_bucket_name` is empty (the default), `true` otherwise.
    Must be set explicitly if the access log bucket is being created at the same time as this module is being invoked.
    EOF
}

variable "origin_s3_access_log_bucket_name" {
  type        = string
  default     = ""
  description = "Name of the existing S3 bucket where S3 Access Logs for the origin Bucket will be delivered. Default is not to enable S3 Access Logging for the origin Bucket."
}

variable "origin_s3_access_log_bucket_name_rendering_enabled" {
  type        = bool
  description = <<-EOT
  If set to `true`, then the S3 origin access logs bucket name will be rendered by calling `format("%v-%v-%v-%v", var.namespace, var.environment, var.stage, var.origin_s3_access_log_bucket_name)`.
  Otherwise, the value for `origin_s3_access_log_bucket_name` will need to be the globally unique name of the access logs bucket.

  For example, if this component produces an origin bucket named `eg-ue1-devplatform-example` and `origin_s3_access_log_bucket_name` is set to
  `example-s3-access-logs`, then the bucket name will be rendered to be `eg-ue1-devplatform-example-s3-access-logs`.
  EOT
  default     = false
}

variable "origin_s3_access_log_prefix" {
  type        = string
  default     = ""
  description = "Prefix to use for S3 Access Log object keys. Defaults to `logs/$${module.this.id}`"
}

variable "origin_force_destroy" {
  type        = bool
  default     = false
  description = "A boolean string that indicates all objects should be deleted from the origin Bucket so that the Bucket can be destroyed without error. These objects are not recoverable."
}

variable "origin_versioning_enabled" {
  type        = bool
  default     = false
  description = "Enable or disable versioning for the origin Bucket. Versioning is a means of keeping multiple variants of an object in the same bucket."
}

variable "origin_deployment_principal_arns" {
  type        = list(string)
  description = "List of role ARNs to grant deployment permissions to the origin Bucket."
  default     = []
}

variable "origin_deployment_actions" {
  type = list(string)
  default = [
    "s3:PutObject",
    "s3:PutObjectAcl",
    "s3:GetObject",
    "s3:DeleteObject",
    "s3:ListBucket",
    "s3:ListBucketMultipartUploads",
    "s3:GetBucketLocation",
    "s3:AbortMultipartUpload"
  ]
  description = "List of actions to permit `origin_deployment_principal_arns` to perform on bucket and bucket prefixes (see `origin_deployment_principal_arns`)"
}

variable "origin_allow_ssl_requests_only" {
  type        = bool
  default     = true
  description = "Set to `true` in order to have the origin bucket require requests to use Secure Socket Layer (HTTPS/SSL). This will explicitly deny access to HTTP requests"
}

variable "block_origin_public_access_enabled" {
  type        = bool
  default     = true
  description = "When set to 'true' the s3 origin bucket will have public access block enabled."
}

variable "origin_encryption_enabled" {
  type        = bool
  default     = true
  description = "When set to 'true' the origin Bucket will have aes256 encryption enabled by default."
}

variable "cloudfront_allowed_methods" {
  type        = list(string)
  default     = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
  description = "List of allowed methods (e.g. GET, PUT, POST, DELETE, HEAD) for AWS CloudFront."
}

variable "cloudfront_cached_methods" {
  type        = list(string)
  default     = ["GET", "HEAD"]
  description = "List of cached methods (e.g. GET, PUT, POST, DELETE, HEAD)."
}

variable "cloudfront_compress" {
  type        = bool
  default     = false
  description = "Compress content for web requests that include Accept-Encoding: gzip in the request header."
}

variable "cloudfront_custom_error_response" {
  type = list(object({
    error_caching_min_ttl = optional(string, "10")
    error_code            = string
    response_code         = string
    response_page_path    = string
  }))

  description = "List of one or more custom error response element maps."
  default     = []
}

variable "cloudfront_access_log_create_bucket" {
  type        = bool
  default     = true
  description = <<-EOT
    When `true` and `cloudfront_access_logging_enabled` is also true, this module will create a new,
    separate S3 bucket to receive CloudFront Access Logs.
    EOT
}

variable "cloudfront_access_log_bucket_name" {
  type        = string
  default     = ""
  description = <<-EOT
    When `cloudfront_access_log_create_bucket` is `false`, this is the name of the existing S3 Bucket where
    CloudFront Access Logs are to be delivered and is required. IGNORED when `cloudfront_access_log_create_bucket` is `true`.
    EOT
}

variable "cloudfront_access_log_bucket_name_rendering_enabled" {
  type        = bool
  description = <<-EOT
  If set to `true`, then the CloudFront origin access logs bucket name will be rendered by calling `format("%v-%v-%v-%v", var.namespace, var.environment, var.stage, var.cloudfront_access_log_bucket_name)`.
  Otherwise, the value for `cloudfront_access_log_bucket_name` will need to be the globally unique name of the access logs bucket.

  For example, if this component produces an origin bucket named `eg-ue1-devplatform-example` and `cloudfront_access_log_bucket_name` is set to
  `example-cloudfront-access-logs`, then the bucket name will be rendered to be `eg-ue1-devplatform-example-cloudfront-access-logs`.
  EOT
  default     = false
}

variable "cloudfront_access_log_prefix" {
  type        = string
  default     = ""
  description = "Prefix to use for CloudFront Access Log object keys. Defaults to no prefix."
}

variable "cloudfront_access_log_prefix_rendering_enabled" {
  type        = bool
  default     = false
  description = "Whether or not to dynamically render $${module.this.id} at the end of `var.cloudfront_access_log_prefix`."
}

variable "cloudfront_aws_shield_protection_enabled" {
  description = "Enable or disable AWS Shield Advanced protection for the CloudFront distribution. If set to 'true', a subscription to AWS Shield Advanced must exist in this account."
  type        = bool
  default     = false
}

variable "cloudfront_aws_waf_protection_enabled" {
  description = <<-EOT
  Enable or disable AWS WAF for the CloudFront distribution.

  This assumes that the `aws-waf-acl-default-cloudfront` component has been deployed to the regional stack corresponding
  to `var.waf_acl_environment`.
  EOT
  type        = bool
  default     = true
}

variable "cloudfront_aws_waf_environment" {
  type        = string
  description = "The environment where the WAF ACL for CloudFront distribution exists."
  default     = null
}

variable "cloudfront_aws_waf_component_name" {
  type        = string
  description = "The name of the component used when deploying WAF ACL"
  default     = "waf"
}

variable "cloudfront_default_root_object" {
  type        = string
  default     = "index.html"
  description = "Object that CloudFront return when requests the root URL."
}

variable "cloudfront_default_ttl" {
  type        = number
  default     = 60
  description = "Default amount of time (in seconds) that an object is in a CloudFront cache."
}

variable "cloudfront_min_ttl" {
  type        = number
  default     = 0
  description = "Minimum amount of time that you want objects to stay in CloudFront caches."
}

variable "cloudfront_max_ttl" {
  type        = number
  default     = 31536000
  description = "Maximum amount of time (in seconds) that an object is in a CloudFront cache."
}

variable "cloudfront_index_document" {
  type        = string
  default     = "index.html"
  description = "Amazon S3 returns this index document when requests are made to the root domain or any of the subfolders."
}

variable "cloudfront_ipv6_enabled" {
  type        = bool
  default     = true
  description = "Set to true to enable an AAAA DNS record to be set as well as the A record."
}

variable "cloudfront_viewer_protocol_policy" {
  type        = string
  description = "Limit the protocol users can use to access content. One of `allow-all`, `https-only`, or `redirect-to-https`."
  default     = "redirect-to-https"
}

variable "cloudfront_lambda_function_association" {
  type = list(object({
    event_type   = string
    include_body = bool
    lambda_arn   = string
  }))

  description = "A config block that configures the CloudFront distribution with lambda@edge functions for specific events."
  default     = []
}

variable "custom_origins" {
  type = list(object({
    domain_name = string
    origin_id   = string
    origin_path = string
    custom_headers = list(object({
      name  = string
      value = string
    }))
    custom_origin_config = object({
      http_port                = number
      https_port               = number
      origin_protocol_policy   = string
      origin_ssl_protocols     = list(string)
      origin_keepalive_timeout = number
      origin_read_timeout      = number
    })
  }))
  default     = []
  description = <<-EOT
    A list of additional custom website [origins](https://www.terraform.io/docs/providers/aws/r/cloudfront_distribution.html#origin-arguments) for this distribution.
    EOT
}

variable "dns_delegated_environment_name" {
  description = "The environment where `dns-delegated` component is deployed to"
  type        = string
  default     = "gbl"
}

variable "failover_criteria_status_codes" {
  type        = list(string)
  description = "List of HTTP Status Codes to use as the origin group failover criteria."
  default = [
    403,
    404,
    500,
    502
  ]
}

variable "failover_s3_origin_format" {
  type        = string
  description = <<-EOT
  If `var.failover_s3_origin_environment` is supplied, this is the format to use for the failover S3 origin bucket name when
  building the name via `format([format], var.namespace, var.failover_s3_origin_environment, var.stage, var.name)`
  and then looking it up via the `aws_s3_bucket` Data Source.

  For example, if this component creates an origin of name `eg-ue1-devplatform-example` and `var.failover_s3_origin_environment`
  is set to `uw1`, then it is expected that a bucket with the name `eg-uw1-devplatform-example-failover` exists in `us-west-1`.
  EOT
  default     = "%v-%v-%v-%v-failover"
}

variable "failover_s3_origin_environment" {
  type        = string
  description = <<-EOT
  The [fixed name](https://github.com/cloudposse/terraform-aws-utils/blob/399951e552483a4f4c1dc7fbe2675c443f3dbd83/main.tf#L10) of the AWS Region where the
  failover S3 origin exists. Setting this variable will enable use of a failover S3 origin, but it is required for the
  failover S3 origin to exist beforehand. This variable is used in conjunction with `var.failover_s3_origin_format` to
  build out the name of the Failover S3 origin in the specified region.

  For example, if this component creates an origin of name `eg-ue1-devplatform-example` and this variable is set to `uw1`,
  then it is expected that a bucket with the name `eg-uw1-devplatform-example-failover` exists in `us-west-1`.
  EOT
  default     = null
}

variable "forward_cookies" {
  type        = string
  default     = "none"
  description = "Specifies whether you want CloudFront to forward all or no cookies to the origin. Can be 'all' or 'none'"
}

variable "forward_header_values" {
  type        = list(string)
  description = "A list of whitelisted header values to forward to the origin (incompatible with `cache_policy_id`)"
  default     = ["Access-Control-Request-Headers", "Access-Control-Request-Method", "Origin"]
}

variable "ordered_cache" {
  type = list(object({
    target_origin_id = string
    path_pattern     = string

    allowed_methods    = list(string)
    cached_methods     = list(string)
    compress           = bool
    trusted_signers    = list(string)
    trusted_key_groups = list(string)

    cache_policy_name          = optional(string)
    cache_policy_id            = optional(string)
    origin_request_policy_name = optional(string)
    origin_request_policy_id   = optional(string)

    viewer_protocol_policy     = string
    min_ttl                    = number
    default_ttl                = number
    max_ttl                    = number
    response_headers_policy_id = string

    forward_query_string              = bool
    forward_header_values             = list(string)
    forward_cookies                   = string
    forward_cookies_whitelisted_names = list(string)

    lambda_function_association = list(object({
      event_type   = string
      include_body = bool
      lambda_arn   = string
    }))

    function_association = list(object({
      event_type   = string
      function_arn = string
    }))

    origin_request_policy = optional(object({
      cookie_behavior       = optional(string, "none")
      header_behavior       = optional(string, "none")
      query_string_behavior = optional(string, "none")

      cookies       = optional(list(string), [])
      headers       = optional(list(string), [])
      query_strings = optional(list(string), [])
    }), {})
  }))
  default     = []
  description = <<-EOT
    An ordered list of [cache behaviors](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudfront_distribution#cache-behavior-arguments) resource for this distribution.
    List in order of precedence (first match wins). This is in addition to the default cache policy.
    Set `target_origin_id` to `""` to specify the S3 bucket origin created by this module.
    Set `cache_policy_id` to `""` to use `cache_policy_name` for creating a new policy. At least one of the two must be set.
    Set `origin_request_policy_id` to `""` to use `origin_request_policy_name` for creating a new policy. At least one of the two must be set.
    EOT
}

variable "preview_environment_enabled" {
  type        = bool
  description = <<-EOT
  Enable or disable SPA Preview Environments via Lambda@Edge, i.e. mapping `subdomain.example.com` to the `/subdomain`
  path in the origin S3 bucket.

  This variable implicitly affects the following variables:

  * `s3_website_enabled`
  * `s3_website_password_enabled`
  * `block_origin_public_access_enabled`
  * `origin_allow_ssl_requests_only`
  * `forward_header_values`
  * `cloudfront_default_ttl`
  * `cloudfront_min_ttl`
  * `cloudfront_max_ttl`
  * `cloudfront_lambda_function_association`
  EOT
  default     = false
}

variable "github_runners_deployment_principal_arn_enabled" {
  type        = bool
  description = "A flag that is used to decide whether or not to include the GitHub Runner's IAM role in origin_deployment_principal_arns list"
  default     = true
}

variable "github_runners_component_name" {
  type        = string
  description = "The name of the component that deploys GitHub Runners, used in remote-state lookup"
  default     = "github-runners"
}

variable "github_runners_environment_name" {
  type        = string
  description = "The name of the environment where the CloudTrail bucket is provisioned"
  default     = "ue2"
}

variable "github_runners_stage_name" {
  type        = string
  description = "The stage name where the CloudTrail bucket is provisioned"
  default     = "auto"
}

variable "github_runners_tenant_name" {
  type        = string
  description = "The tenant name where the GitHub Runners are provisioned"
  default     = null
}

variable "lambda_edge_functions" {
  type = map(object({
    source = optional(list(object({
      filename = string
      content  = string
    })))
    source_dir   = optional(string)
    source_zip   = optional(string)
    runtime      = string
    handler      = string
    event_type   = string
    include_body = bool
  }))
  description = <<-EOT
  Lambda@Edge functions to create.

  The key of this map is the name of the Lambda@Edge function.

  This map will be deep merged with each enabled default function. Use deep merge to change or overwrite specific values passed by those function objects.
  EOT
  default     = {}
}

variable "lambda_edge_runtime" {
  type        = string
  description = <<-EOT
  The default Lambda@Edge runtime for all functions.

  This value is deep merged in `module.lambda_edge_functions` with `var.lambda_edge_functions` and can be overwritten for any individual function.
  EOT
  default     = "nodejs16.x"
}

variable "lambda_edge_handler" {
  type        = string
  description = <<-EOT
  The default Lambda@Edge handler for all functions.

  This value is deep merged in `module.lambda_edge_functions` with `var.lambda_edge_functions` and can be overwritten for any individual function.
  EOT
  default     = "index.handler"
}

variable "lambda_edge_allowed_ssm_parameters" {
  type        = list(string)
  description = "The Lambda@Edge functions will be allowed to access the list of AWS SSM parameter with these ARNs"
  default     = []
}

variable "lambda_edge_destruction_delay" {
  type        = string
  description = <<-EOT
  The delay, in [Golang ParseDuration](https://pkg.go.dev/time#ParseDuration) format, to wait before destroying the Lambda@Edge
  functions.

  This delay is meant to circumvent Lambda@Edge functions not being immediately deletable following their dissociation from
  a CloudFront distribution, since they are replicated to CloudFront Edge servers around the world.

  If set to `null`, no delay will be introduced.

  By default, the delay is 20 minutes. This is because it takes about 3 minutes to destroy a CloudFront distribution, and
  around 15 minutes until the Lambda@Edge function is available for deletion, in most cases.

  For more information, see: https://github.com/hashicorp/terraform-provider-aws/issues/1721.
  EOT
  default     = "20m"
}

variable "http_version" {
  type        = string
  default     = "http2"
  description = "The maximum HTTP version to support on the distribution. Allowed values are http1.1, http2, http2and3 and http3"
}

variable "comment" {
  type        = string
  description = "Any comments you want to include about the distribution."
  default     = "Managed by Terraform"
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