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

  dns_enabled = local.enabled && var.route53_enabled

  acm_certificate_domain = try(length(var.acm_certificate_domain) > 0, false)? var.acm_certificate_domain : try(length(var.acm_certificate_domain_suffix) > 0, false)? format("%s.%s.%s", var.acm_certificate_domain_suffix, var.environment, module.dns_delegated.outputs.default_domain_name) : format("%s.%s", var.environment, module.dns_delegated.outputs.default_domain_name)

  maintenance_page_fixed_response = {
    content_type = "text/html"
    status_code  = "503"
    message_body = file("${path.module}/${var.maintenance_page_path}")
  }
}

module "target_group_label" {
  source  = "cloudposse/label/null"
  version = "0.25.0"

  name = "default"

  tenant      = ""
  namespace   = ""
  stage       = ""
  environment = ""

  context = module.this.context
}

resource "aws_security_group" "default" {
  count       = local.enabled? 1 : 0
  name        = module.this.id
  description = "ECS cluster EC2 autoscale capacity providers"
  vpc_id      = module.vpc.outputs.vpc_id
}

resource "aws_security_group_rule" "ingress_cidr" {
  for_each          = local.enabled? toset(var.allowed_cidr_blocks) : []
  type              = "ingress"
  from_port         = 0
  to_port           = 65535
  protocol          = "tcp"
  cidr_blocks       = [each.value]
  security_group_id = join("", aws_security_group.default[*].id)
  description       = "Allow inbound traffic from specified CIDR blocks"
}

resource "aws_security_group_rule" "ingress_security_groups" {
  for_each                 = local.enabled? toset(var.allowed_security_groups) : []
  type                     = "ingress"
  from_port                = 0
  to_port                  = 65535
  protocol                 = "tcp"
  source_security_group_id = each.value
  security_group_id        = join("", aws_security_group.default[*].id)
  description              = "Allow inbound traffic from specified security groups"
}

resource "aws_security_group_rule" "egress" {
  count             = local.enabled? 1 : 0
  type              = "egress"
  from_port         = 0
  to_port           = 65535
  protocol          = "tcp"
  cidr_blocks       = ["10.0.0.0/8"]
  security_group_id = join("", aws_security_group.default[*].id)
  description       = "Allow outbound traffic to specified CIDR blocks"
}

module "cluster" {
  source  = "cloudposse/ecs-cluster/aws"
  version = "0.4.1"

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
        subnet_ids                  = var.internal_enabled? module.vpc.outputs.private_subnet_ids : module.vpc.outputs.public_subnet_ids
        associate_public_ip_address =!var.internal_enabled
      }
    )
  }
}

resource "aws_route53_record" "default" {
  for_each = local.dns_enabled? var.alb_configuration : {}
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
  count       = local.enabled? 1 : 0
  domain      = local.acm_certificate_domain
  statuses    = ["ISSUED"]
  most_recent = true
}

module "alb" {
  source  = "cloudposse/alb/aws"
  version = "1.11.1"

  for_each = local.enabled? var.alb_configuration : {}

  vpc_id          = module.vpc.outputs.vpc_id
  subnet_ids      = lookup(each.value, "internal_enabled", var.internal_enabled)? module.vpc.outputs.private_subnet_ids : module.vpc.outputs.public_subnet_ids
  ip_address_type = lookup(each.value, "ip_address_type", "ipv4")

  internal = lookup(each.value, "internal_enabled", var.internal_enabled)

  security_group_enabled = lookup(each.value, "security_group_enabled", true)
  security_group_ids     = [module.vpc.outputs.vpc_default_security_group_id]

  http_enabled             = lookup(each.value, "http_enabled", true)
  http_port                = lookup(each.value, "http_port", 80)
  http_redirect            = lookup(each.value, "http_redirect", true)
  http_ingress_cidr_blocks = lookup(each.value, "http_ingress_cidr_blocks", var.alb_ingress_cidr_blocks_http)

  https_enabled             = lookup(each.value, "https_enabled", true)
  https_port                = lookup(each.value, "https_port", 443)
  https_ingress_cidr_blocks = lookup(each.value, "https_ingress_cidr_blocks", var.alb_ingress_cidr_blocks_https)
  certificate_arn           = lookup(each.value, "certificate_arn", one(data.aws_acm_certificate.default[*].arn))

  access_logs_enabled                     = lookup(each.value, "access_logs_enabled", true)
  alb_access_logs_s3_bucket_force_destroy = lookup(each.value, "alb_access_logs_s3_bucket_force_destroy", true)

  lifecycle_rule_enabled = lookup(each.value, "lifecycle_rule_enabled", true)

  expiration_days                    = lookup(each.value, "expiration_days", 90)
  noncurrent_version_expiration_days = lookup(each.value, "noncurrent_version_expiration_days", 90)
  standard_transition_days           = lookup(each.value, "standard_transition_days", 30)
  noncurrent_version_transition_days = lookup(each.value, "noncurrent_version_transition_days", 30)

  enable_glacier_transition = lookup(each.value, "enable_glacier_transition", true)
  glacier_transition_days   = lookup(each.value, "glacier_transition_days", 60)

  stickiness                        = lookup(each.value, "stickiness", null)
  cross_zone_load_balancing_enabled = lookup(each.value, "cross_zone_load_balancing_enabled", true)

  target_group_name        = join(module.target_group_label.delimiter, [module.target_group_label.id, each.key])
  target_group_port        = lookup(each.value, "target_group_port", 80)
  target_group_protocol    = lookup(each.value, "target_group_protocol", "HTTP")
  target_group_target_type = lookup(each.value, "target_group_target_type", "ip")

  health_check_interval            = lookup(each.value, "health_check_interval", 300)
  health_check_healthy_threshold   = lookup(each.value, "health_check_healthy_threshold", 2)
  health_check_matcher             = lookup(each.value, "health_check_matcher", "200-399")
  health_check_path                = lookup(each.value, "health_check_path", "/")
  health_check_port                = lookup(each.value, "health_check_port", "traffic-port")
  health_check_timeout             = lookup(each.value, "health_check_timeout", 100)
  health_check_unhealthy_threshold = lookup(each.value, "health_check_unhealthy_threshold", 10)

  deregistration_delay = lookup(each.value, "deregistration_delay", 15)

  listener_http_fixed_response  = local.maintenance_page_fixed_response
  listener_https_fixed_response = local.maintenance_page_fixed_response

  attributes = lookup(each.value, "attributes", [each.key])

  context = module.this.context
}

locals {
  certificate_domains = merge([
    for config_key, config in var.alb_configuration :
    { for domain in config.additional_certs :
    "${config_key}_${domain}" => domain } if length(lookup(config, "additional_certs", [])) > 0
  ]...)
}

resource "aws_lb_listener_certificate" "additional_certs" {
  for_each = local.certificate_domains

  listener_arn    = module.alb[split("_", each.key)[0]].https_listener_arn
  certificate_arn = data.aws_acm_certificate.additional_certs[each.key].arn
}
data "aws_acm_certificate" "additional_certs" {
  for_each = local.certificate_domains

  domain = each.value
}

output "cluster_arn" {
  value       = module.cluster.arn
  description = "ECS cluster ARN"
}

output "cluster_name" {
  value       = module.cluster.name
  description = "ECS Cluster Name"
}

output "vpc_id" {
  value       = module.vpc.outputs.vpc_id
  description = "VPC ID"
}

output "security_group_id" {
  value       = module.vpc.outputs.vpc_default_security_group_id
  description = "Security group id"
}

output "public_subnet_ids" {
  value       = module.vpc.outputs.public_subnet_ids
  description = "Public subnet ids"
}

output "private_subnet_ids" {
  value       = module.vpc.outputs.private_subnet_ids
  description = "Private subnet ids"
}

output "alb" {
  value       = module.alb
  description = "ALB outputs"
}

output "records" {
  value       = local.dns_enabled? { for record, value in aws_route53_record.default : record => value.fqdn } : {}
  description = "Record names"
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

module "vpc" {
  source  = "cloudposse/stack-config/yaml//modules/remote-state"
  version = "1.5.0"

  component = "vpc"

  context = module.this.context
}

module "dns_delegated" {
  source  = "cloudposse/stack-config/yaml//modules/remote-state"
  version = "1.5.0"

  component   = var.dns_delegated_component_name
  stage       = var.dns_delegated_stage_name
  environment = var.dns_delegated_environment_name

  context = module.this.context
}

variable "region" {
  type        = string
  description = "AWS Region"
}

variable "alb_configuration" {
  type        = map(any)
  default     = {}
  description = "Map of multiple ALB configurations."
}

variable "alb_ingress_cidr_blocks_http" {
  type        = list(string)
  default     = ["0.0.0.0/0"]
  description = "List of CIDR blocks allowed to access environment over HTTP"
}

variable "alb_ingress_cidr_blocks_https" {
  type        = list(string)
  default     = ["0.0.0.0/0"]
  description = "List of CIDR blocks allowed to access environment over HTTPS"
}

variable "route53_enabled" {
  type        = bool
  default     = true
  description = "Whether or not to create a route53 record for the ALB"
}

variable "acm_certificate_domain" {
  type        = string
  default     = null
  description = "Domain to get the ACM cert to use on the ALB."
}

variable "acm_certificate_domain_suffix" {
  type        = string
  default     = null
  description = "Domain suffix to use with dns delegated HZ to get the ACM cert to use on the ALB"
}

variable "route53_record_name" {
  type        = string
  default     = "*"
  description = "The route53 record name"
}

variable "internal_enabled" {
  type        = bool
  default     = false
  description = "Whether to create an internal load balancer for services in this cluster"
}

variable "maintenance_page_path" {
  type        = string
  default     = "templates/503_example.html"
  description = "The path from this directory to the text/html page to use as the maintenance page. Must be within 1024 characters"
}

variable "container_insights_enabled" {
  type        = bool
  default     = true
  description = "Whether or not to enable container insights"
}

variable "dns_delegated_stage_name" {
  type        = string
  default     = null
  description = "Use this stage name to read from the remote state to get the dns_delegated zone ID"
}

variable "dns_delegated_environment_name" {
  type        = string
  default     = "gbl"
  description = "Use this environment name to read from the remote state to get the dns_delegated zone ID"
}

variable "dns_delegated_component_name" {
  type        = string
  default     = "dns-delegated"
  description = "Use this component name to read from the remote state to get the dns_delegated zone ID"
}

variable "allowed_security_groups" {
  type        = list(string)
  default     = []
  description = "List of Security Group IDs to be allowed to connect to the ECS cluster"
}

variable "allowed_cidr_blocks" {
  type        = list(string)
  default     = []
  description = "List of CIDR blocks to be allowed to connect to the ECS cluster"
}

variable "capacity_providers_fargate" {
  description = "Use FARGATE capacity provider"
  type        = bool
  default     = true
}

variable "capacity_providers_fargate_spot" {
  description = "Use FARGATE_SPOT capacity provider"
  type        = bool
  default     = false
}

variable "capacity_providers_ec2" {
  description = "EC2 autoscale groups capacity providers"
  type = map(object({
    instance_type                        = string
    max_size                             = number
    security_group_ids                   = optional(list(string), [])
    min_size                             = optional(number, 0)
    image_id                             = optional(string)
    instance_initiated_shutdown_behavior = optional(string, "terminate")
    key_name                             = optional(string, "")
    user_data                            = optional(string, "")
    enable_monitoring                    = optional(bool, true)
    instance_warmup_period               = optional(number, 300)
    maximum_scaling_step_size            = optional(number, 1)
    minimum_scaling_step_size            = optional(number, 1)
    target_capacity_utilization          = optional(number, 100)
    ebs_optimized                        = optional(bool, false)
    block_device_mappings = optional(list(object({
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
    })), [])
    instance_market_options = optional(object({
      market_type = string
      spot_options = object({
        block_duration_minutes         = number
        instance_interruption_behavior = string
        max_price                      = number
        spot_instance_type             = string
        valid_until                    = string
      })
    }))
    instance_refresh = optional(object({
      strategy = string
      preferences = optional(object({
        instance_warmup        = optional(number, null)
        min_healthy_percentage = optional(number, null)
        skip_matching          = optional(bool, null)
        auto_rollback          = optional(bool, null)
      }), null)
      triggers = optional(list(string), [])
    }))
    mixed_instances_policy = optional(object({
      instances_distribution = object({
        on_demand_allocation_strategy            = string
        on_demand_base_capacity                  = number
        on_demand_percentage_above_base_capacity = number
        spot_allocation_strategy                 = string
        spot_instance_pools                      = number
        spot_max_price                           = string
      })
      }), {
      instances_distribution = null
    })
    placement = optional(object({
      affinity          = string
      availability_zone = string
      group_name        = string
      host_id           = string
      tenancy           = string
    }))
    credit_specification = optional(object({
      cpu_credits = string
    }))
    elastic_gpu_specifications = optional(object({
      type = string
    }))
    disable_api_termination   = optional(bool, false)
    default_cooldown          = optional(number, 300)
    health_check_grace_period = optional(number, 300)
    force_delete              = optional(bool, false)
    termination_policies      = optional(list(string), ["Default"])
    suspended_processes       = optional(list(string), [])
    placement_group           = optional(string, "")
    metrics_granularity       = optional(string, "1Minute")
    enabled_metrics = optional(list(string), [
      "GroupMinSize",
      "GroupMaxSize",
      "GroupDesiredCapacity",
      "GroupInServiceInstances",
      "GroupPendingInstances",
      "GroupStandbyInstances",
      "GroupTerminatingInstances",
      "GroupTotalInstances",
      "GroupInServiceCapacity",
      "GroupPendingCapacity",
      "GroupStandbyCapacity",
      "GroupTerminatingCapacity",
      "GroupTotalCapacity",
      "WarmPoolDesiredCapacity",
      "WarmPoolWarmedCapacity",
      "WarmPoolPendingCapacity",
      "WarmPoolTerminatingCapacity",
      "WarmPoolTotalCapacity",
      "GroupAndWarmPoolDesiredCapacity",
      "GroupAndWarmPoolTotalCapacity",
    ])
    wait_for_capacity_timeout            = optional(string, "10m")
    service_linked_role_arn              = optional(string, "")
    metadata_http_endpoint_enabled       = optional(bool, true)
    metadata_http_put_response_hop_limit = optional(number, 2)
    metadata_http_tokens_required        = optional(bool, true)
    metadata_http_protocol_ipv6_enabled  = optional(bool, false)
    tag_specifications_resource_types    = optional(set(string), ["instance", "volume"])
    max_instance_lifetime                = optional(number, null)
    capacity_rebalance                   = optional(bool, false)
    warm_pool = optional(object({
      pool_state                  = string
      min_size                    = number
      max_group_prepared_capacity = number
    }))
  }))
  default = {}
  validation {
    condition     =!contains(["FARGATE", "FARGATE_SPOT"], keys(var.capacity_providers_ec2))
    error_message = "'FARGATE' and 'FARGATE_SPOT' name is reserved"
  }
}

terraform {
  required_version = ">= 1.3.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 4.0"
    }
  }
}