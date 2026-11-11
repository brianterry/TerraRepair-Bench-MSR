```hcl
module "cloudmap_namespace" {
  for_each = { for service_connect in var.service_connect_configurations : service_connect.namespace => service_connect }

  source  = "cloudposse/stack-config/yaml//modules/remote-state"
  version = "1.5.0"

  component = each.key

  ignore_errors = true
  context       = module.this.context
}

locals {
  valid_cloudmap_namespaces      = { for k, v in module.cloudmap_namespace : k => v if v.outputs!= null }
  service_connect_configurations = [for service_connect in var.service_connect_configurations : merge(service_connect, { namespace = try(local.valid_cloudmap_namespaces[service_connect.namespace].outputs.name, service_connect.namespace) })]
}

module "cloudmap_namespace_service_discovery" {
  for_each = { for service_connect in var.service_registries : service_connect.namespace => service_connect }

  source  = "cloudposse/stack-config/yaml//modules/remote-state"
  version = "1.5.0"

  component = each.key

  ignore_errors = true
  context       = module.this.context
}

locals {
  valid_cloudmap_service_discovery_namespaces = { for k, v in module.cloudmap_namespace_service_discovery : k => v if v.outputs!= null }
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
  default_datadog_tags = var.datadog_logging_default_tags_enabled? {
    env     = module.this.stage
    account = format("%s-%s-%s", module.this.tenant, module.this.environment, module.this.stage)
  } : null

  all_dd_tags = join(",", [for k, v in merge(local.default_datadog_tags, var.datadog_logging_tags) : format("%s:%s", k, v)])

  datadog_logconfiguration_firelens = {
    logDriver = "awsfirelens"
    options = var.datadog_agent_sidecar_enabled? {
      Name           = "datadog",
      apikey         = module.datadog_configuration.datadog_api_key,
      Host           = format("http-intake.logs.%s", module.datadog_configuration.datadog_site)
      dd_service     = module.this.name,
      dd_tags        = local.all_dd_tags,
      dd_source      = "ecs",
      dd_message_key = "log",
      TLS            = "on",
      provider       = "ecs"
    } : {}
  }
}

module "datadog_sidecar_logs" {
  source  = "cloudposse/cloudwatch-logs/aws"
  version = "0.6.6"

  count = local.enabled && var.datadog_agent_sidecar_enabled && var.datadog_sidecar_containers_logs_enabled? 1 : 0

  stream_names      = lookup(var.logs, "stream_names", [])
  retention_in_days = lookup(var.logs, "retention_in_days", 90)

  principals = merge({
    Service = ["ecs.amazonaws.com", "ecs-tasks.amazonaws.com"]
  }, lookup(var.logs, "principals", {}))

  additional_permissions = concat([
    "logs:CreateLogStream",
    "logs:DeleteLogStream",
  ], lookup(var.logs, "additional_permissions", []))

  context = module.this.context
}

module "datadog_container_definition" {
  source  = "cloudposse/ecs-container-definition/aws"
  version = "0.58.1"

  count = local.enabled && var.datadog_agent_sidecar_enabled? 1 : 0

  container_cpu    = 256
  container_memory = 512
  container_name   = "datadog-agent"
  container_image  = "public.ecr.aws/datadog/agent:latest"
  essential        = true
  map_environment = {
    "ECS_FARGATE"                          = var.task.launch_type == "FARGATE"? true : false
    "DD_API_KEY"                           = module.datadog_configuration.datadog_api_key
    "DD_SITE"                              = module.datadog_configuration.datadog_site
    "DD_ENV"                               = module.this.stage
    "DD_LOGS_ENABLED"                      = true
    "DD_LOGS_CONFIG_CONTAINER_COLLECT_ALL" = true
    "SD_BACKEND"                           = "docker"
    "DD_PROCESS_AGENT_ENABLED"             = true
    "DD_DOGSTATSD_NON_LOCAL_TRAFFIC"       = true
    "DD_APM_ENABLED"                       = true
    "DD_CONTAINER_LABELS_AS_TAGS" = jsonencode({
      "org.opencontainers.image.revision" = "version"
    })
  }

  port_mappings = [{
    containerPort = 8125
    hostPort      = 8125
    protocol      = "udp"
    }, {
    containerPort = 8126
    hostPort      = 8126
    protocol      = "tcp"
  }]

  log_configuration = var.datadog_sidecar_containers_logs_enabled? {
    logDriver = "awslogs"
    options = {
      "awslogs-group"         = one(module.datadog_sidecar_logs[*].log_group_name)
      "awslogs-region"        = var.region
      "awslogs-stream-prefix" = "datadog-agent"
    }
  } : null
}

module "datadog_fluent_bit_container_definition" {
  source  = "cloudposse/ecs-container-definition/aws"
  version = "0.58.1"

  count = local.enabled && var.datadog_agent_sidecar_enabled? 1 : 0

  container_cpu    = 256
  container_memory = 512
  container_name   = "datadog-log-router"
  container_image = "amazon/aws-for-fluent-bit:stable"
  essential       = true
  firelens_configuration = {
    type = "fluentbit"
    options = {
      config-file-type        = "file",
      config-file-value       = "/fluent-bit/configs/parse-json.conf",
      enable-ecs-log-metadata = "true"
    }
  }

  log_configuration = var.datadog_sidecar_containers_logs_enabled? {
    logDriver = "awslogs"
    options = {
      "awslogs-group"         = one(module.datadog_sidecar_logs[*].log_group_name)
      "awslogs-region"        = var.region
      "awslogs-stream-prefix" = "datadog-log-router"
    }
  } : null
}

variable "github_oidc_trusted_role_arns" {
  type        = list(string)
  description = "A list of IAM Role ARNs allowed to assume this cluster's GitHub OIDC role"
  default     = []
}

variable "github_actions_ecspresso_enabled" {
  type        = bool
  description = "Create IAM policies required for deployments with Ecspresso"
  default     = false
}

locals {
  github_actions_iam_policy = data.aws_iam_policy_document.github_actions_iam_policy.json
}

data "aws_iam_policy_document" "github_actions_iam_policy" {
  source_policy_documents = compact([
    data.aws_iam_policy_document.github_actions_iam_platform_policy.json,
    join("", data.aws_iam_policy_document.github_actions_iam_ecspresso_policy[*]["json"])
  ])
}

data "aws_iam_policy_document" "github_actions_iam_platform_policy" {
  dynamic "statement" {
    for_each = length(var.github_oidc_trusted_role_arns) == 0? [] : ["enabled"]
    content {
      sid    = "TrustedRoleAccess"
      effect = "Allow"
      actions = [
        "sts:AssumeRole",
        "sts:TagSession"
      ]
      resources = var.github_oidc_trusted_role_arns
    }
  }

  statement {
    sid    = "AllowKMSAccess"
    effect = "Allow"
    actions = [
      "kms:Decrypt",
      "kms:DescribeKey"
    ]
    resources = [
      "*"
    ]
  }

  statement {
    effect = "Allow"
    actions = [
      "ssm:GetParameters",
      "ssm:GetParameter",
      "ssm:PutParameter"
    ]
    resources = concat([
      "arn:aws:ssm:*:*:parameter${format("/%s/%s/*", var.chamber_service, var.name)}"
    ], formatlist("arn:aws:ssm:*:*:parameter%s", keys(local.url_params)))
  }

  statement {
    effect = "Allow"
    actions = [
      "ssm:DescribeParameters",
      "ssm:GetParametersByPath"
    ]
    resources = [
      "*"
    ]
  }
}

data "aws_caller_identity" "current" {}

locals {
  aws_partition = module.iam_roles.aws_partition
  account_id    = data.aws_caller_identity.current.account_id
}

data "aws_iam_policy_document" "github_actions_iam_ecspresso_policy" {
  count = var.github_actions_ecspresso_enabled? 1 : 0

  statement {
    effect = "Allow"
    actions = [
      "ecs:DescribeServices",
      "ecs:UpdateService",
      "ecs:ListTagsForResource"
    ]
    resources = [
      join("", module.ecs_alb_service_task[*]["service_arn"])
    ]
  }

  statement {
    effect = "Allow"
    actions = [
      "ecs:RunTask",
    ]
    resources = [
      format("arn:%s:ecs:%s:%s:task-definition/%s:*", local.aws_partition, var.region, local.account_id, join("", module.ecs_alb_service_task.*.task_definition_family)),
    ]
  }

  statement {
    effect = "Allow"
    actions = [
      "ecs:RegisterTaskDefinition",
      "ecs:TagResource",
      "ecs:DescribeTaskDefinition",
      "ecs:DescribeTasks",
      "application-autoscaling:DescribeScalableTargets"
    ]
    resources = [
      "*"
    ]
  }

  statement {
    sid    = "logs"
    effect = "Allow"
    actions = [
      "logs:Describe*",
      "logs:Get*",
      "logs:List*",
      "logs:StartQuery",
      "logs:StopQuery",
      "logs:TestMetricFilter",
      "logs:FilterLogEvents",
      "oam:ListSinks"
    ]
    resources = [
      "*"
    ]
  }

  statement {
    effect = "Allow"
    actions = [
      "iam:PassRole"
    ]
    resources = [
      join("", module.ecs_alb_service_task[*]["task_exec_role_arn"]),
      join("", module.ecs_alb_service_task[*]["task_role_arn"]),
    ]
  }

  dynamic "statement" {
    for_each = local.s3_mirroring_enabled? ["enabled"] : []
    content {
      effect    = "Allow"
      actions   = ["s3:ListBucket"]
      resources = ["*"]
    }
  }

  dynamic "statement" {
    for_each = local.s3_mirroring_enabled? ["enabled"] : []
    content {
      effect = "Allow"
      actions = [
        "s3:PutObject",
        "s3:GetObject",
        "s3:HeadObject",
      ]
      resources = [
        format("%s/%s/%s/*", lookup(module.s3[0].outputs, "bucket_arn", null), module.ecs_cluster.outputs.cluster_name, module.this.id)
      ]
    }
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
  count              = local.github_actions_iam_role_enabled? 1 : 0
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
  enabled = module.this.enabled

  s3_mirroring_enabled = local.enabled && try(length(var.s3_mirror_name) > 0, false)

  service_container = lookup(var.containers, "service")
  container_port = try(lookup(local.service_container, "port_mappings")[0].containerPort, null)

  assign_public_ip = lookup(local.task, "assign_public_ip", false)

  container_definition = concat([
    for container in module.container_definition :
    container.json_map_object
    ],
    [
      for container in module.datadog_container_definition :
      container.json_map_object
    ],
    var.datadog_log_method_is_firelens? [
      for container in module.datadog_fluent_bit_container_definition :
      container.json_map_object
    ] : [],
  )

  kinesis_kms_id = try(one(data.aws_kms_alias.selected[*].id), null)

  use_alb_security_group = local.is_alb? lookup(local.task, "use_alb_security_group", true) : false

  task_definition_s3_key     = format("%s/%s/task-definition.json", module.ecs_cluster.outputs.cluster_name, module.this.id)
  task_definition_use_s3     = local.enabled && local.s3_mirroring_enabled && contains(flatten(data.aws_s3_objects.mirror[*].keys), local.task_definition_s3_key)
  task_definition_s3_objects = flatten(data.aws_s3_objects.mirror[*].keys)

  task_definition_s3 = try(jsondecode(data.aws_s3_object.task_definition[0].body), {})

  task_s3 = local.task_definition_use_s3? {
    launch_type  = try(local.task_definition_s3.requiresCompatibilities[0], null)
    network_mode = lookup(local.task_definition_s3, "networkMode", null)
    task_memory  = try(tonumber(lookup(local.task_definition_s3, "memory")), null)
    task_cpu     = try(tonumber(lookup(local.task_definition_s3, "cpu")), null)
  } : {}

  task = merge(var.task, local.task_s3)

  efs_component_volumes = lookup(local.task, "efs_component_volumes", [])
  efs_component_map = {
    for efs in local.efs_component_volumes : efs["name"] => efs
  }
  efs_component_remote_state = {
    for efs in local.efs_component_volumes : efs["name"] => module.efs[efs["name"]].outputs
  }
  efs_component_merged = [
    for efs_volume_name, efs_component_output in local.efs_component_remote_state : {
      host_path = local.efs_component_map[efs_volume_name].host_path
      name      = efs_volume_name
      efs_volume_configuration = [
        {
          file_system_id          = efs_component_output.efs_id
          root_directory          = local.efs_component_map[efs_volume_name].efs_volume_configuration[0].root_directory
          transit_encryption      = local.efs_component_map[efs_volume_name].ef "  s " = " github " = " =module "  = " = " = = = = = = = = = " = " = = = = =: = " = " = = " = " = = =module =module = = = = = = module =module " =module = " s = "aws =module =module =modulemodule " = =module = =module =module =module =module =module =module modulemodulemodule "aws "modulemodule "module = "module "module = "s =
 =module "
 =
 = =module module =module = = = "aws "cloudmodule "module "module  =module = = = = = = = = = "cloud "  " = = = "modulemodule = = "s =module = " aws =module = " s = = = " = " = " = = s
 = = = = =module =module = = = = = "s =
 = "s = =
 = "module =s
 = "s = = = = = = "module = = = = = = = = = = "modulemodulemodule =modulemodule source =module =module "module =module = "module "module =module

 =module = = = = = " =module " = "container "module = " = "module "module " : = "module = " = = = = =  =
 "module "module = =module =module =
 " smodule =module =module = =module =enabled =module "
 = = = = = = =
 =
 = " =
 =
 = "module = = =
 = = =
 = = " =

 " = "module =module = = =module =attributes = = = " github = =module =module =module = = = = "module = "module = "s " github =
s = " : " = "smodule = "s
smodule "module "s
 = = = = = = = =module =
 = " = " = "module
 =module = " = " : "module
module =module =module = =module = "module = =module =module = " = " = " =module =module = " = = " = =


 = "s =s = "module " = = = = = = = "module = = = "enabled : " =
module = =module = = = = " s =var = = "s = = =smodule = = = = " = local = =module s github = = = = =
 =module github s
 = = = = =
module = = = = =
 =module =s =
s
 github = = ".module = = = = = "module =
 =
module = " =
smodule =
module = = = =
 =module = = "cloud =module =
module =modulemodule = = "s = "s
module =
 =
 =modulemodule = =module =module = =
 = = = = " s
 =
 = =module =module = " = " =
 = = "for = =contextmodule module = "module = = module =
module =module = local =
 = =smodule =
 =
 =modulemodule = = s
 = =
 = s =smodule =
s =module = " =
 =
 =
 =module " = "modulemodule = "s
 local




 = = = local

 =
 =
 = = "modulemoduless = = = = = = =


s
 =


 =
module s
 =
 =



 = " s = " =
 = "s
s
s {
 = local =s = = " = = =
 local = = "s = "s
s = = "s

 =
 = " github = =module = =
 = " s
 = = " = "s {
 = = "s {
 = " = "s " = =
 = = "aws "

 = " = " s

 = " = " = "s
 = = = = "aws.module = " = = = "s
s
s
 =

 = =s




module = " =


module =
 =s
s
s =s = =
 =
 =module module = " = "s
s
 = = = "s {
 = = =s {
 = = = = =
 = " = "smodule " = = = =module = = " = " =
 =s
 =s
 = " = "s

 = " =s = = " = = = = = " = local =
 = " = = "module = = module module githubmodule " =
 = = =
 = "module " s =

 = = =aws = " = = " = " = = = " = = = = = =
 = = " = "s
 = v
 = "s {
module = "s = " = "  "s
module module =module = " = = = " = = " = " = " =modules ss = s
 = =
 = = = " = "s = =module github githubmodule " = = = = = = = = " : container = "s
 aws github s
 = = = "  = " = " = " = = = " = " = " aws = "aws = " ec "s
 "aws "module "
 = = " github =

 = "aws "s
 = " = "aws =



 "

 " github "module "module "

 = " github " = "container = local

module " = " = " = = =
 = "module "module " module modulemodule module github role role
 = "github = = = = local = = local =
 =
 = = = " version =module = = local = =

 = "enabled local =
 = = =
 =


 =


 =
 = "
module =
 = = local =
 =module " = "s

attributes = local
module

 = " =
attributes =attributes = attributes attributes attributes = =attributes attributess =

 = =moduleattributes attributesattributesattributes = localattributes attributes attributesattributes attributes "attributes
 = = = locals
s ss s

ss =

 =s









 =
 =module =
 attributes =s

 =
 = local =varcontainer

 "container


attributes =module =



 "container =

 =module "

 =
 = =




 attributes attributesattributes =



 =
 =
 = " =





 "role =

 = "attributes = " = "
 = "attributes
 for =attributes = " =
 =
 =attributes =namespace =


 =
 =attributes = "module "module =
 = attributes
 = attributes =
 =
module module attributes
 =

attributes attributes attributesattributesattributes attributes =

s
 = =attributes = attributes = attributes = "cloud = " = = attributes = attributes

s
attributes =
 s =attributes

 =
 = github = =attributes = "s = = = module =
 github "s s = =module = =s = =module "s =module =modulemodule =module = " =module = = " = " = "
s
 =
 = = =module =
 =
 = "s
 = " = "modulemodule =moduleattributes =
 = =module =
 =module = =module =module =
 = = = = = = =
 =
s =s =s =module =module = " = "s =module =
 =module =
module =module =


 =module =module =smodule = = = = =module s
module "s =module = =
 = module =
 =
 =

 s


 = " = " s
 =
 = " =
 =
 =
 =s
 github = =
 = {
 =
 =
 =
 =



 = "module =module:module =module =


 =module =module "
 = " =
 = = = =  s
s
s
 = "s
 =module =



 = "role = = = local =module =module = "s
 " s





 =module github "module module = "s
 =module "scontainer = "s


 =
 =
 = "s
 = "s

 =


smodule " = " = "s = = " =
 "enabled =

 =s
 =

 =s
 = =: s
 = " = "

 =module

 = " s
 = " = " =
 = = "s =
 = = =s

 =attributes =s =
 =aws = "sattributes =attributes = " = " =module = =module =module = = = = " =



 s
s
 = attributes =
 =

 s =
 =
 =
 = = = = "s


 s =module =
 = ss

 = = =module = = = attributes = local = local = local

container =module =
 =module =attributes = module = =container =module = = module = = =module =module =attributes = attributes = container = local = =
formodule = local = = = " =


 = " =module = module = = " = {
 =
 =module =s
 =


 container = {
 = local =module =github " = "container
 = = = =module =module =attributes = local =
 = local = " s =module =module =
 = = s

module = " = =

 =module = =aws =module =module =module =



 =module s
 =
smodule attributes =

s




modulemodule = "s = =module "s = = =
 =
 = "modulemodule s
module " = " = " =
 =modulemodule


 =
 = "

 = " = " =
 =local = "


 =attributes =

 =





 =attributes =



 = =module


 =





 =


 =
 =

 =
 = "s
modulemodule =
modules
 =



s
s








s





 =

s
s s






module =module "



 = " github =
 =






 =

s
s
s =
 =s


s
s
s



 =s
 =


ss













 =
ss
s =
 = "s

 s s

 =
s



 =
 =s
attributes

s

 s
smodule aws =
 =:s





s

s
s


s
s




s

s









 s


 "s

 "ss


s
s
s
s
s
s
s
s
s
s
 = "s =s

s

s
 =
 =module s "s {
 = ss
s awss = s
 =attributes =attributes =
 =
 = =
 " s
enabled = = = s
 =sss = " s
 s
s
s
s

 =

s
s = "s =


 = "

 =module =
 = =

 = "s



 aws =






s





s = s
container =


 = =s
 = version =



s

s