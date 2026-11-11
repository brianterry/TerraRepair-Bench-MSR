module "this" {
  source  = "git::https://github.com/cloudposse/terraform-null-label.git?ref=4be135e9d9769a47705dcdbf78161a633e3b63d9"

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

module "api_gateway_rest_api" {
  source  = "git::https://github.com/cloudposse/terraform-aws-api-gateway.git?ref=5a0a5e0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a"

  enabled = local.enabled

  openapi_config           = var.openapi_config
  endpoint_type            = var.endpoint_type
  logging_level            = var.logging_level
  metrics_enabled          = var.metrics_enabled
  xray_tracing_enabled     = var.xray_tracing_enabled
  access_log_format        = var.access_log_format
  rest_api_policy          = var.rest_api_policy
  private_link_target_arns = module.nlb[*].nlb_arn
  access_logs_enabled      = true
  cache_cluster_size       = "0.5"

  context = module.this.context
}

resource "aws_api_gateway_domain_name" "this" {
  count                    = local.enabled ? 1 : 0
  domain_name              = local.domain_name
  regional_certificate_arn = data.aws_acm_certificate.issued[0].arn
  security_policy          = "TLS_1_2"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = module.this.tags
}

module "nlb" {
  source  = "git::https://github.com/cloudposse/terraform-aws-nlb.git?ref=3f4d0f3f4d0f3f4d0f3f4d0f3f4d0f3f4d0f3f4d"
  count   = var.enable_private_link_nlb ? 1 : 0

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
  source  = "git::https://github.com/cloudposse/terraform-aws-stack-config.git//modules/remote-state?ref=1e9e0a11e9e0a11e9e0a11e9e0a11e9e0a11e9e0a"
  version = "1.5.0"

  component   = "dns-delegated"
  environment = module.iam_roles.global_environment_name

  context = module.this.context
}

module "acm" {
  source  = "git::https://github.com/cloudposse/terraform-aws-stack-config.git//modules/remote-state?ref=1e9e0a11e9e0a11e9e0a11e9e0a11e9e0a11e9e0a"
  version = "1.5.0"

  component     = "acm"
  ignore_errors = true

  defaults = {
    domain_name = ""
  }

  context = module.this.context
}

module "vpc" {
  source  = "git::https://github.com/cloudposse/terraform-aws-stack-config.git//modules/remote-state?ref=1e9e0a11e9e0a11e9e0a11e9e0a11e9e0a11e9e0a"
  version = "1.5.0"

  component = "vpc"

  context = module.this.context
}