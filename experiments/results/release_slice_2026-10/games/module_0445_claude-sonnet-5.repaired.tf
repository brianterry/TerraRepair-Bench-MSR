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
  source = "git::https://github.com/cloudposse/terraform-null-label.git?ref=7bf2aa3cf5b35d3e5d1dfd9f88ea7e22f9a3b1aa"

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


data "aws_partition" "current" {
  count = local.enabled ? 1 : 0
}

# The Spacelift always validates its credentials, so we always pass api_key_id and api_key_secret
data "aws_ssm_parameter" "spacelift_key_id" {
  name = "/spacelift/key_id"
}

data "aws_ssm_parameter" "spacelift_key_secret" {
  name = "/spacelift/key_secret"
}

data "aws_ami" "spacelift" {
  count = local.enabled && var.spacelift_ami_id == null ? 1 : 0

  owners      = var.custom_spacelift_ami ? ["self"] : [var.spacelift_aws_account_id]
  most_recent = true

  filter {
    name   = "name"
    values = ["spacelift-*"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = var.architecture
  }
}


module "iam_label" {
  source = "git::https://github.com/cloudposse/terraform-null-label.git?ref=7bf2aa3cf5b35d3e5d1dfd9f88ea7e22f9a3b1aa"

  attributes = var.iam_attributes

  context = module.this.context
}

data "aws_iam_policy_document" "assume_role_policy" {
  count = local.enabled ? 1 : 0

  statement {
    actions = [
      "sts:AssumeRole",
      "sts:SetSourceIdentity",
      "sts:TagSession",
    ]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

locals {
  identity_account_name = module.account_map.outputs.identity_account_account_name
  role_arn_template     = module.account_map.outputs.iam_role_arn_templates[local.identity_account_name]
}

data "aws_iam_policy_document" "default" {
  count = local.enabled ? 1 : 0

  statement {
    actions = [
      "sts:AssumeRole",
      "sts:SetSourceIdentity",
      "sts:TagSession",
    ]
    resources = formatlist(local.role_arn_template, ["spacelift"])
  }

  statement {
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    actions = [
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage"
    ]
    resources = [local.ecr_repo_arn]
  }
}

resource "aws_iam_policy" "default" {
  count = local.enabled ? 1 : 0

  name   = module.iam_label.id
  policy = join("", data.aws_iam_policy_document.default[*].json)

  tags = module.iam_label.tags
}

resource "aws_iam_role" "default" {
  count = local.enabled ? 1 : 0

  name               = module.iam_label.id
  assume_role_policy = join("", data.aws_iam_policy_document.assume_role_policy[*].json)
  managed_policy_arns = [
    join("", aws_iam_policy.default[*].arn),
    "arn:${join("", data.aws_partition.current[*].partition)}:iam::aws:policy/AutoScalingReadOnlyAccess",
    "arn:${join("", data.aws_partition.current[*].partition)}:iam::aws:policy/CloudWatchAgentServerPolicy",
    "arn:${join("", data.aws_partition.current[*].partition)}:iam::aws:policy/AmazonSSMManagedInstanceCore",
    "arn:${join("", data.aws_partition.current[*].partition)}:iam::aws:policy/AWSXRayDaemonWriteAccess"
  ]

  tags = module.iam_label.tags
}

resource "aws_iam_instance_profile" "default" {
  count = local.enabled ? 1 : 0

  name = module.iam_label.id
  role = join("", aws_iam_role.default[*].name)

  tags = module.iam_label.tags
}


locals {
  enabled                = module.this.enabled
  vpc_id                 = module.vpc.outputs.vpc_id
  vpc_private_subnet_ids = module.vpc.outputs.private_subnet_ids
  ecr_repo_arn           = module.ecr.outputs.ecr_repo_arn_map[var.ecr_repo_name]
  ecr_repo_url           = module.ecr.outputs.ecr_repo_url_map[var.ecr_repo_name]
  ecr_account_id         = element(split(".", local.ecr_repo_url), 0)
  ecr_region             = coalesce(var.ecr_region, var.region)
  spacelift_runner_image = coalesce(var.spacelift_runner_image, local.ecr_repo_url)
  userdata_template      = "${path.module}/templates/user-data.sh"
  spacelift_service_file = "${path.module}/templates/spacelift@.service"

  spacelift_service_config = <<-END
    #cloud-config
    ${jsonencode({
  write_files = flatten([
    {
      path        = "/etc/systemd/system/spacelift@.service"
      permissions = "0655"
      owner       = "root:root"
      content     = file(local.spacelift_service_file)
    }
    ]
  )
})}
END

space_id = lookup(module.spaces.outputs, var.space_name, "root")
}

resource "spacelift_worker_pool" "primary" {
  count = local.enabled ? 1 : 0

  name        = module.this.id
  description = "Deployed to ${var.region} within '${join("-", compact([module.this.tenant, module.this.stage]))}' AWS account"

  space_id = local.space_id
}

data "cloudinit_config" "config" {
  count = local.enabled ? 1 : 0

  gzip          = false
  base64_encode = true

  part {
    content_type = "text/cloud-config"
    filename     = "spacelift@.service"
    content      = local.spacelift_service_config
  }

  part {
    content_type = "text/x-shellscript"
    filename     = "user-data.sh"
    content = templatefile(local.userdata_template, {
      region                            = var.region
      aws_config_file                   = var.aws_config_file
      aws_profile                       = coalesce(var.aws_profile, "${var.namespace}-identity")
      ecr_region                        = local.ecr_region
      ecr_account_id                    = local.ecr_account_id
      spacelift_runner_image            = local.spacelift_runner_image
      spacelift_worker_pool_private_key = join("", spacelift_worker_pool.primary[*].private_key)
      spacelift_worker_pool_config      = join("", spacelift_worker_pool.primary[*].config)
      spacelift_domain_name             = var.spacelift_domain_name
      github_netrc_enabled              = var.github_netrc_enabled
      github_netrc_ssm_path_token       = var.github_netrc_ssm_path_token
      github_netrc_ssm_path_user        = var.github_netrc_ssm_path_user
      spacelift_agents_per_node         = var.spacelift_agents_per_node
      infracost_enabled                 = var.infracost_enabled
      infracost_api_token_ssm_path      = var.infracost_api_token_ssm_path
      infracost_warn_on_failure         = var.infracost_warn_on_failure
      infracost_cli_args                = var.infracost_cli_args
    })
  }
}

module "security_group" {
  source = "git::https://github.com/cloudposse/terraform-aws-security-group.git?ref=8e59dedf5d3ff5f3b5f9e0e0f24ac7ad53b4c9dd"

  security_group_description = "Security Group for Spacelift worker pool"
  allow_all_egress           = true

  vpc_id = local.vpc_id

  context = module.this.context
}

module "autoscale_group" {
  source = "git::https://github.com/cloudposse/terraform-aws-ec2-autoscale-group.git?ref=a4a4fd59e7f3e11d5e8dfa9b0e6f7a3c23f9b2d4"

  image_id                    = var.spacelift_ami_id == null ? join("", data.aws_ami.spacelift[*].image_id) : var.spacelift_ami_id
  instance_type               = var.instance_type
  mixed_instances_policy      = var.mixed_instances_policy
  subnet_ids                  = local.vpc_private_subnet_ids
  health_check_type           = var.health_check_type
  health_check_grace_period   = var.health_check_grace_period
  user_data_base64            = join("", data.cloudinit_config.config[*].rendered)
  associate_public_ip_address = false
  block_device_mappings       = var.block_device_mappings
  iam_instance_profile_name   = join("", aws_iam_instance_profile.default[*].name)
  security_group_ids          = [module.security_group.id]
  termination_policies        = var.termination_policies
  wait_for_capacity_timeout   = var.wait_for_capacity_timeout
  ebs_optimized               = var.ebs_optimized

  min_size         = var.min_size
  max_size         = var.max_size
  desired_capacity = var.desired_capacity

  # Auto-scaling policies and CloudWatch metric alarms
  autoscaling_policies_enabled           = true
  default_cooldown                       = var.default_cooldown
  scale_down_cooldown_seconds            = var.scale_down_cooldown_seconds
  cpu_utilization_high_threshold_percent = var.cpu_utilization_high_threshold_percent
  cpu_utilization_low_threshold_percent  = var.cpu_utilization_low_threshold_percent

  max_instance_lifetime = var.instance_lifetime

  # The instance refresh definition
  # If this block is configured, an Instance Refresh will be started when the Auto Scaling Group is updated
  instance_refresh        = var.instance_refresh
  launch_template_version = var.instance_refresh == null ? "$Latest" : ""

  context = module.this.context
}


output "worker_pool_id" {
  value       = join("", spacelift_worker_pool.primary[*].id)
  description = "Spacelift worker pool ID"
}

output "worker_pool_name" {
  value       = join("", spacelift_worker_pool.primary[*].name)
  description = "Spacelift worker pool name"
}

output "security_group_id" {
  description = "Spacelift Security Group ID"
  value       = module.security_group.id
}

output "security_group_arn" {
  description = "Spacelift Security Group ARN"
  value       = module.security_group.arn
}

output "security_group_name" {
  description = "Spacelift Security Group Name"
  value       = module.security_group.name
}

output "launch_template_id" {
  description = "The ID of the launch template"
  value       = module.autoscale_group.launch_template_id
}

output "launch_template_arn" {
  description = "The ARN of the launch template"
  value       = module.autoscale_group.launch_template_arn
}

output "autoscaling_group_id" {
  description = "The autoscaling group id"
  value       = module.autoscale_group.autoscaling_group_id
}

output "autoscaling_group_name" {
  description = "The autoscaling group name"
  value       = module.autoscale_group.autoscaling_group_name
}

output "autoscaling_group_arn" {
  description = "The ARN for this AutoScaling Group"
  value       = module.autoscale_group.autoscaling_group_arn
}

output "autoscaling_group_min_size" {
  description = "The minimum size of the autoscale group"
  value       = module.autoscale_group.autoscaling_group_min_size
}

output "autoscaling_group_max_size" {
  description = "The maximum size of the autoscale group"
  value       = module.autoscale_group.autoscaling_group_max_size
}

output "autoscaling_group_default_cooldown" {
  description = "Time between a scaling activity and the succeeding scaling activity"
  value       = module.autoscale_group.autoscaling_group_default_cooldown
}

output "autoscaling_group_health_check_grace_period" {
  description = "Time after instance comes into service before checking health"
  value       = module.autoscale_group.autoscaling_group_health_check_grace_period
}

output "autoscaling_group_health_check_type" {
  description = "`EC2` or `ELB`. Controls how health checking is done"
  value       = module.autoscale_group.autoscaling_group_health_check_type
}

output "iam_role_name" {
  value       = join("", aws_iam_role.default[*].name)
  description = "Spacelift IAM Role name"
}

output "iam_role_id" {
  value       = join("", aws_iam_role.default[*].unique_id)
  description = "Spacelift IAM Role ID"
}

output "iam_role_arn" {
  value       = join("", aws_iam_role.default[*].arn)
  description = "Spacelift IAM Role ARN"
}


# This provider always validates its credentials, so we always pass api_key_id and api_key_secret
provider "spacelift" {
  api_key_endpoint = var.spacelift_api_endpoint
  api_key_id       = data.aws_ssm_parameter.spacelift_key_id.value
  api_key_secret   = data.aws_ssm_parameter.spacelift_key_secret.value
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
  source  = "../../account-map/modules/iam-roles"
  context = module.this.context
}


module "account_map" {
  source = "git::https://github.com/cloudposse/terraform-yaml-stack-config.git//modules/remote-state?ref=f3f01e8acbbf1d671a3a9617a69e75b14be34e60"

  component   = "account-map"
  environment = try(coalesce(var.account_map_environment_name, module.this.environment), null)
  stage       = var.account_map_stage_name
  tenant      = try(coalesce(var.account_map_tenant_name, module.this.tenant), null)

  context = module.this.context
}

module "ecr" {
  source = "git::https://github.com/cloudposse/terraform-yaml-stack-config.git//modules/remote-state?ref=f3f01e8acbbf1d671a3a9617a69e75b14be34e60"

  component   = "ecr"
  environment = try(coalesce(var.ecr_environment_name, module.this.environment), null)
  stage       = var.ecr_stage_name
  tenant      = try(coalesce(var.ecr_tenant_name, module.this.tenant), null)

  context = module.this.context
}

module "vpc" {
  source = "git::https://github.com/cloudposse/terraform-yaml-stack-config.git//modules/remote-state?ref=f3f01e8acbbf1d671a3a9617a69e75b14be34e60"

  component = "vpc"

  context = module.this.context
}

module "spaces" {
  source = "git::https://github.com/cloudposse/terraform-yaml-stack-config.git//modules/remote-state?ref=f3f01e8acbbf1d671a3a9617a69e75b14be34e60"

  component   = var.spacelift_spaces_component_name
  environment = try(coalesce(var.spacelift_spaces_environment_name, module.this.environment), null)
  stage       = try(coalesce(var.spacelift_spaces_stage_name, module.this.stage), null)
  tenant      = try(coalesce(var.spacelift_spaces_tenant_name, module.this.tenant), null)

  context = module.this.context
}


variable "region" {
  type        = string
  description = "AWS Region"
}

variable "mixed_instances_policy" {
  description = "Policy to use a mixed group of on-demand/spot of different types. Launch template is automatically generated. https://www.terraform.io/docs/providers/aws/r/autoscaling_group.html#mixed_instances_policy-1"

  type = object({
    instances_distribution = object({
      on_demand_allocation_strategy            = string
      on_demand_base_capacity                  = number
      on_demand_percentage_above_base_capacity = number
      spot_allocation_strategy                 = string
      spot_instance_pools                      = number
      spot_max_price                           = string
    })
    override = list(object({
      instance_type     = string
      weighted_capacity = number
    }))
  })
  default = null
}

variable "ebs_optimized" {
  type        = bool
  description = "If true, the launched EC2 instance will be EBS-optimized"
  default     = false
}

variable "max_size" {
  type        = number
  description = "The maximum size of the autoscale group"
}

variable "min_size" {
  type        = number
  description = "The minimum size of the autoscale group"
}

variable "desired_capacity" {
  type        = number
  description = "The number of Amazon EC2 instances that should be running in the group, if not set will use `min_size` as value"
  default     = null
}

variable "wait_for_capacity_timeout" {
  type        = string
  description = "A maximum duration that Terraform should wait for ASG instances to be healthy before timing out. (See also Waiting for Capacity below.) Setting this to '0' causes Terraform to skip all Capacity Waiting behavior"
}

variable "cpu_utilization_high_threshold_percent" {
  type        = number
  description = "CPU utilization high threshold"
}

variable "cpu_utilization_low_threshold_percent" {
  type        = number
  description = "CPU utilization low threshold"
}

variable "instance_lifetime" {
  type        = number
  default     = 1209600
  description = "Number of seconds after which the instance will be terminated. The default is set to 14 days."
}

variable "default_cooldown" {
  type        = number
  description = "The amount of time, in seconds, after a scaling activity completes before another scaling activity can start"
  default     = 300
}

variable "scale_down_cooldown_seconds" {
  type        = number
  default     = 300
  description = "The amount of time, in seconds, after a scaling activity completes and before the next scaling activity can start"
}

variable "health_check_type" {
  type        = string
  description = "Controls how health checking is done. Valid values are `EC2` or `ELB`"
  default     = "EC2"
}

variable "health_check_grace_period" {
  type        = number
  description = "Time (in seconds) after instance comes into service before checking health"
  default     = 300
}

variable "termination_policies" {
  description = "A list of policies to decide how the instances in the auto scale group should be terminated. The allowed values are `OldestInstance`, `NewestInstance`, `OldestLaunchConfiguration`, `ClosestToNextInstanceHour`, `Default`"
  type        = list(string)
  default     = ["OldestLaunchConfiguration"]
}

variable "block_device_mappings" {
  description = "Specify volumes to attach to the instance besides the volumes specified by the AMI"

  type = list(object({
    device_name  = string
    no_device    = bool
    virtual_name = string
    ebs = object({
      delete_on_termination = bool
      encrypted             = bool
      iops                  = number
      kms_key_id            = string
      snapshot_id           = string
      volume_size           = number
      volume_type           = string
    })
  }))

  default = []
}

variable "account_map_environment_name" {
  type        = string
  description = "The name of the environment where `account_map` is provisioned"
  default     = "gbl"
}

variable "account_map_stage_name" {
  type        = string
  description = "The name of the stage where `account_map` is provisioned"
  default     = "root"
}

variable "account_map_tenant_name" {
  type        = string
  description = <<-EOT
  The name of the tenant where `account_map` is provisioned.

  If the `tenant` label is not used, leave this as `null`.
  EOT
  default     = null
}

variable "ecr_environment_name" {
  type        = string
  description = "The name of the environment where `ecr` is provisioned"
  default     = ""
}

variable "ecr_stage_name" {
  type        = string
  description = "The name of the stage where `ecr` is provisioned"
  default     = "artifacts"
}

variable "ecr_tenant_name" {
  type        = string
  description = <<-EOT
  The name of the tenant where `ecr` is provisioned.

  If the `tenant` label is not used, leave this as `null`.
  EOT
  default     = null
}


variable "ecr_region" {
  type        = string
  description = "AWS region that contains the ECR infrastructure repo"
  default     = ""
}

variable "ecr_repo_name" {
  type        = string
  description = "ECR repository name"
}

variable "instance_type" {
  type        = string
  description = "EC2 instance type to use for workers"
  default     = "r5n.large"
}

variable "spacelift_runner_image" {
  type        = string
  description = "URL of ECR image to use for Spacelift"
  default     = ""
}

variable "spacelift_api_endpoint" {
  type        = string
  description = "The Spacelift API endpoint URL (e.g. https://example.app.spacelift.io)"
}

variable "spacelift_ami_id" {
  type        = string
  description = "AMI ID of Spacelift worker pool image"
  default     = null
}

variable "custom_spacelift_ami" {
  type        = bool
  description = "Custom spacelift AMI"
  default     = false
}

variable "architecture" {
  type        = list(string)
  description = "OS architecture of the EC2 instance AMI"
  default     = ["x86_64"]
}

variable "spacelift_domain_name" {
  type        = string
  description = "Top-level domain name to use for pulling the launcher binary"
  default     = "spacelift.io"
}

variable "iam_attributes" {
  type        = list(string)
  description = "Additional attributes to add to the IDs of the IAM role and policy"
  default     = []
}

variable "launch_template_version" {
  type        = string
  description = "Launch template version to use for workers. Note that instance refresh settings are IGNORED unless template version is empty"
  default     = "$Latest"
}

variable "instance_refresh" {
  description = "The instance refresh definition. If this block is configured, an Instance Refresh will be started when the Auto Scaling Group is updated"
  type = object({
    strategy = string
    preferences = object({
      instance_warmup        = optional(number, null)
      min_healthy_percentage = optional(number, null)
      skip_matching          = optional(bool, null)
      auto_rollback          = optional(bool, null)
    })
    triggers = optional(list(string), [])
  })

  default = null
}

variable "github_netrc_enabled" {
  type        = bool
  description = "Whether to create a GitHub .netrc file so Spacelift can clone private GitHub repositories."
  default     = false
}

variable "github_netrc_ssm_path_token" {
  type        = string
  description = "If `github_netrc` is enabled, this is the SSM path to retrieve the GitHub token."
  default     = "/github/token"
}

variable "github_netrc_ssm_path_user" {
  type        = string
  description = "If `github_netrc` is enabled, this is the SSM path to retrieve the GitHub user"
  default     = "/github/user"
}

variable "infracost_enabled" {
  type        = bool
  description = "Whether to enable infracost for Spacelift stacks"
  default     = false
}

variable "infracost_api_token_ssm_path" {
  type        = string
  description = "This is the SSM path to retrieve and set the INFRACOST_API_TOKEN environment variable"
  default     = "/infracost/token"
}

variable "infracost_cli_args" {
  type        = string
  description = "These are the CLI args passed to infracost"
  default     = ""
}

variable "infracost_warn_on_failure" {
  type        = bool
  description = "A failure executing Infracost, or a non-zero exit code being returned from the command will cause runs to fail. If this is true, this will only warn instead of failing the stack."
  default     = true
}

variable "aws_config_file" {
  type        = string
  description = "The AWS_CONFIG_FILE used by the worker. Can be overridden by `/.spacelift/config.yml`."
  default     = "/etc/aws-config/aws-config-spacelift"
}

variable "aws_profile" {
  type        = string
  description = <<-EOT
    The AWS_PROFILE used by the worker. If not specified, `"$${var.namespace}-identity"` will be used.
    Can be overridden by `/.spacelift/config.yml`.
    EOT
  default     = null
}

variable "spacelift_agents_per_node" {
  type        = number
  description = "Number of Spacelift agents to run on one worker node. NOTE: This affects billable units. Spacelift charges per agent."
  default     = 1
}

variable "spacelift_aws_account_id" {
  type        = string
  description = "AWS Account ID owned by Spacelift"
  default     = "643313122712"
}

variable "space_name" {
  type        = string
  description = "The name of the Space to create the worker pool in"
  default     = "root"
}

variable "spacelift_spaces_component_name" {
  type        = string
  description = "The name of the spacelift spaces component"
  default     = "spacelift/spaces"
}

variable "spacelift_spaces_environment_name" {
  type        = string
  description = "The environment name of the spacelift spaces component"
  default     = null
}

variable "spacelift_spaces_stage_name" {
  type        = string
  description = "The stage name of the spacelift spaces component"
  default     = null
}

variable "spacelift_spaces_tenant_name" {
  type        = string
  description = "The tenant name of the spacelift spaces component"
  default     = null
}


terraform {
  required_version = ">= 1.0.0"

  required_providers {
    spacelift = {
      source  = "spacelift-io/spacelift"
      version = ">= 0.1.2"
    }
    aws = {
      source  = "hashicorp/aws"
      version = ">= 4.9.0"
    }
    cloudinit = {
      source  = "hashicorp/cloudinit"
      version = ">= 2.2.0"
    }
  }
}