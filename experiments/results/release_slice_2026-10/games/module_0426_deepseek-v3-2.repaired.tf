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



data "aws_iam_policy_document" "ssosync_lambda_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "ssosync_lambda_identity_center" {
  statement {
    effect = "Allow"
    actions = [
      "identitystore:DeleteUser",
      "identitystore:CreateGroup",
      "identitystore:CreateGroupMembership",
      "identitystore:ListGroups",
      "identitystore:ListUsers",
      "identitystore:ListGroupMemberships",
      "identitystore:IsMemberInGroups",
      "identitystore:GetGroupMembershipId",
      "identitystore:DeleteGroupMembership",
      "identitystore:DeleteGroup",
      "secretsmanager:GetSecretValue",
      "kms:Decrypt"
    ]
    resources = ["*"]
  }
  statement {
    effect = "Allow"
    actions = [
      "logs:PutLogEvents",
      "logs:CreateLogStream",
      "logs:CreateLogGroup"
    ]
    resources = ["arn:aws:logs:*:*:*"]
  }
}

resource "aws_iam_role" "default" {
  count = local.enabled ? 1 : 0

  name               = module.this.id
  assume_role_policy = data.aws_iam_policy_document.ssosync_lambda_assume_role.json

  inline_policy {
    name   = "ssosync_lambda_identity_center"
    policy = data.aws_iam_policy_document.ssosync_lambda_identity_center.json
  }
}


locals {
  enabled                    = module.this.enabled
  google_credentials         = one(data.aws_ssm_parameter.google_credentials[*].value)
  scim_endpoint_url          = one(data.aws_ssm_parameter.scim_endpoint_url[*].value)
  scim_endpoint_access_token = one(data.aws_ssm_parameter.scim_endpoint_access_token[*].value)
  identity_store_id          = one(data.aws_ssm_parameter.identity_store_id[*].value)

  ssosync_artifact_url = "${var.ssosync_url_prefix}/${var.ssosync_version}/ssosync_Linux_${var.architecture}.tar.gz"

  download_artifact = "ssosync.tar.gz"
}

data "aws_ssm_parameter" "google_credentials" {
  count = local.enabled ? 1 : 0
  name  = "${var.google_credentials_ssm_path}/google_credentials"
}

data "aws_ssm_parameter" "scim_endpoint_url" {
  count = local.enabled ? 1 : 0
  name  = "${var.google_credentials_ssm_path}/scim_endpoint_url"
}

data "aws_ssm_parameter" "scim_endpoint_access_token" {
  count = local.enabled ? 1 : 0
  name  = "${var.google_credentials_ssm_path}/scim_endpoint_access_token"
}

data "aws_ssm_parameter" "identity_store_id" {
  count = local.enabled ? 1 : 0
  name  = "${var.google_credentials_ssm_path}/identity_store_id"
}


module "ssosync_artifact" {
  count = local.enabled ? 1 : 0

  source  = "cloudposse/module-artifact/external"
  version = "0.8.0"

  filename    = local.download_artifact
  module_name = "ssosync"
  module_path = path.module
  url         = local.ssosync_artifact_url
}

resource "null_resource" "extract_my_tgz" {
  count = local.enabled ? 1 : 0

  provisioner "local-exec" {
    command = "tar -xzf ${local.download_artifact} -C dist"
  }

  depends_on = [module.ssosync_artifact]
}

data "archive_file" "lambda" {
  count = local.enabled ? 1 : 0

  type        = "zip"
  source_file = "dist/ssosync"
  output_path = "ssosync.zip"

  depends_on = [null_resource.extract_my_tgz]
}


resource "aws_lambda_function" "ssosync" {
  count = local.enabled ? 1 : 0

  function_name    = module.this.id
  filename         = "ssosync.zip"
  source_code_hash = module.ssosync_artifact[0].base64sha256
  description      = "Syncs Google Workspace users and groups to AWS SSO"
  role             = aws_iam_role.default[0].arn
  handler          = "ssosync"
  runtime          = "provided.al2023"
  timeout          = 300
  memory_size      = 128
  vpc_config {
    subnet_ids         = var.subnet_ids
    security_group_ids = var.security_group_ids
  }
  dead_letter_config {
    target_arn = aws_sqs_queue.ssosync_dlq[0].arn
  }
  tracing_config {
    mode = "Active"
  }
  kms_key_arn = aws_kms_key.lambda_env[0].arn
  code_signing_config_arn = aws_lambda_code_signing_config.ssosync[0].arn
  reserved_concurrent_executions = var.reserved_concurrent_executions

  environment {
    variables = {
      SSOSYNC_LOG_LEVEL          = var.log_level
      SSOSYNC_LOG_FORMAT         = var.log_format
      SSOSYNC_GOOGLE_CREDENTIALS = local.google_credentials
      SSOSYNC_GOOGLE_ADMIN       = var.google_admin_email
      SSOSYNC_SCIM_ENDPOINT      = local.scim_endpoint_url
      SSOSYNC_SCIM_ACCESS_TOKEN  = local.scim_endpoint_access_token
      SSOSYNC_REGION             = var.region
      SSOSYNC_IDENTITY_STORE_ID  = local.identity_store_id
      SSOSYNC_USER_MATCH         = var.google_user_match
      SSOSYNC_GROUP_MATCH        = var.google_group_match
      SSOSYNC_SYNC_METHOD        = var.sync_method
      SSOSYNC_IGNORE_GROUPS      = var.ignore_groups
      SSOSYNC_IGNORE_USERS       = var.ignore_users
      SSOSYNC_INCLUDE_GROUPS     = var.include_groups
      SSOSYNC_LOAD_ASM_SECRETS   = false
    }
  }
  depends_on = [null_resource.extract_my_tgz, data.archive_file.lambda]
}

resource "aws_sqs_queue" "ssosync_dlq" {
  count = local.enabled ? 1 : 0
  name  = "${module.this.id}-dlq"
}

resource "aws_kms_key" "lambda_env" {
  count = local.enabled ? 1 : 0
  description = "KMS key for Lambda environment variable encryption"
  enable_key_rotation = true
}

resource "aws_lambda_code_signing_config" "ssosync" {
  count = local.enabled ? 1 : 0
  allowed_publishers {
    signing_profile_version_arns = [aws_signer_signing_profile.ssosync[0].arn]
  }
  policies {
    untrusted_artifact_on_deployment = "Warn"
  }
}

resource "aws_signer_signing_profile" "ssosync" {
  count = local.enabled ? 1 : 0
  platform_id = "AWSLambda-SHA384-ECDSA"
}

resource "aws_cloudwatch_event_rule" "ssosync" {
  count = var.enabled ? 1 : 0

  name                = module.this.id
  description         = "Run ssosync on a schedule"
  schedule_expression = var.schedule_expression

}

resource "aws_cloudwatch_event_target" "ssosync" {
  count = var.enabled ? 1 : 0

  rule      = aws_cloudwatch_event_rule.ssosync[0].name
  target_id = module.this.id
  arn       = aws_lambda_function.ssosync[0].arn
}


resource "aws_lambda_permission" "allow_cloudwatch_execution" {
  count = local.enabled ? 1 : 0

  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ssosync[0].arn
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.ssosync[0].arn
}


output "arn" {
  description = "ARN of the lambda function"
  value       = one(aws_lambda_function.ssosync[*].arn)
}

output "invoke_arn" {
  description = "Invoke ARN of the lambda function"
  value       = one(aws_lambda_function.ssosync[*].invoke_arn)
}

output "qualified_arn" {
  description = "ARN identifying your Lambda Function Version (if versioning is enabled via publish = true)"
  value       = one(aws_lambda_function.ssosync[*].qualified_arn)
}


provider "aws" {
  region = var.region
}


variable "region" {
  type        = string
  description = "AWS Region where AWS SSO is enabled"
}

variable "schedule_expression" {
  type        = string
  description = "Schedule for trigger the execution of ssosync (see CloudWatch schedule expressions)"
  default     = "rate(15 minutes)"
}

variable "log_level" {
  type        = string
  description = "Log level for Lambda function logging"
  default     = "warn"

  validation {
    condition     = contains(["panic", "fatal", "error", "warn", "info", "debug", "trace"], var.log_level)
    error_message = "Allowed values: `panic`, `fatal`, `error`, `warn`, `info`, `debug`, `trace`"
  }
}

variable "log_format" {
  type        = string
  description = "Log format for Lambda function logging"
  default     = "json"

  validation {
    condition     = contains(["json", "text"], var.log_format)
    error_message = "Allowed values: `json`, `text`"
  }
}

variable "ssosync_url_prefix" {
  type        = string
  description = "URL prefix for ssosync binary"
  default     = "https://github.com/Benbentwo/ssosync/releases/download"
}

variable "ssosync_version" {
  type        = string
  description = "Version of ssosync to use"
  default     = "v2.0.2"
}

variable "architecture" {
  type        = string
  description = "Architecture of the Lambda function"
  default     = "x86_64"
}

variable "google_credentials_ssm_path" {
  type        = string
  description = "SSM Path for `ssosync` secrets"
  default     = "/ssosync"
}

variable "google_admin_email" {
  type        = string
  description = "Google Admin email"
}

variable "google_user_match" {
  type        = string
  description = "Google Workspace user filter query parameter, example: 'name:John* email:admin*', see: https://developers.google.com/admin-sdk/directory/v1/guides/search-users"
  default     = ""
}

variable "google_group_match" {
  type        = string
  description = "Google Workspace group filter query parameter, example: 'name:Admin* email:aws-*', see: https://developers.google.com/admin-sdk/directory/v1/guides/search-groups"
  default     = ""
}

variable "ignore_groups" {
  type        = string
  description = "Ignore these Google Workspace groups"
  default     = ""
}

variable "ignore_users" {
  type        = string
  description = "Ignore these Google Workspace users"
  default     = ""
}

variable "include_groups" {
  type        = string
  description = "Include only these Google Workspace groups. (Only applicable for sync_method user_groups)"
  default     = ""
}

variable "sync_method" {
  type        = string
  description = "Sync method to use"
  default     = "groups"

  validation {
    condition     = contains(["groups", "users_groups"], var.sync_method)
    error_message = "Allowed values: `groups`, `users_groups`"
  }
}

variable "subnet_ids" {
  type        = list(string)
  description = "Subnet IDs for Lambda VPC configuration"
}

variable "security_group_ids" {
  type        = list(string)
  description = "Security Group IDs for Lambda VPC configuration"
}

variable "reserved_concurrent_executions" {
  type        = number
  description = "Reserved concurrent executions for Lambda function"
  default     = -1
}


terraform {
  required_version = ">= 1.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 4.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = ">= 2.3.0"
    }
    null = {
      source  = "hashicorp/null"
      version = ">= 3.0"
    }
  }
}