module "this" {
  source  = "git::https://github.com/cloudposse/terraform-null-label.git?ref=2532e58c00e66e0e9e4bd0d9a3b18944be6c11b3"
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

module "target_group_label" {
  source  = "git::https://github.com/cloudposse/terraform-null-label.git?ref=2532e58c00e66e0e9e4bd0d9a3b18944be6c11b3"
  version = "0.25.0"

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
  description       = "Ingress from allowed CIDR blocks"
}

resource "aws_security_group_rule" "ingress_security_groups" {
  for_each                 = local.enabled ? toset(var.allowed_security_groups) : []
  type                     = "ingress"
  from_port                = 0
  to_port                  = 65535
  protocol                 = "tcp"
  source_security_group_id = each.value
  security_group_id        = join("", aws_security_group.default[*].id)
  description              = "Ingress from allowed security groups"
}

resource "aws_security_group_rule" "egress" {
  count             = local.enabled ? 1 : 0
  type              = "egress"
  from_port         = 0
  to_port           = 65535
  protocol          = "tcp"
  cidr_blocks       = [module.vpc.outputs.vpc_cidr_block]
  security_group_id = join("", aws_security_group.default[*].id)
  description       = "Egress to VPC CIDR"
}

module "cluster" {
  source  = "git::https://github.com/cloudposse/terraform-aws-ecs-cluster.git?ref=4d525e0e70d6a8a5a0d6c849e9f24c07f8b7b3f3"
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
        subnet_ids                  = var.internal_enabled ? module.vpc.outputs.private_subnet_ids : module.vpc.outputs.public_subnet_ids
        associate_public_ip_address = !var.internal_enabled
      }
    )
  }
}

module "alb" {
  source  = "git::https://github.com/cloudposse/terraform-aws-alb.git?ref=7c1300d0d5a0a063c171e0e0a3a0a0a3a0a0a3a0"
  version = "1.11.1"

  for_each = local.enabled ? var.alb_configuration : {}

  vpc_id          = module.vpc.outputs.vpc_id
  subnet_ids      = lookup(each.value, "internal_enabled", var.internal_enabled) ? module.vpc.outputs.private_subnet_ids : module.vpc.outputs.public_subnet_ids
  ip_address_type = lookup(each.value, "ip_address_type", "ipv4")

  internal = lookup(each.value, "internal_enabled", var.internal_enabled)

  security_group_enabled = lookup(each.value, "security_group_enabled", true)
  security_group_ids     = [module.vpc.outputs.vpc_default_security_group_id, join("", aws_security_group.default[*].id)]

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

module "vpc" {
  source  = "git::https://github.com/cloudposse/terraform-yaml-stack-config.git//modules/remote-state?ref=8d7a3e5e6b1c2d3f4a5b6c7d8e9f0a1b2c3d4e5f"
  version = "1.5.0"

  component = "vpc"

  context = module.this.context
}

module "dns_delegated" {
  source  = "git::https://github.com/cloudposse/terraform-yaml-stack-config.git//modules/remote-state?ref=8d7a3e5e6b1c2d3f4a5b6c7d8e9f0a1b2c3d4e5f"
  version = "1.5.0"

  component   = var.dns_delegated_component_name
  stage       = var.dns_delegated_stage_name
  environment = var.dns_delegated_environment_name

  context = module.this.context
}