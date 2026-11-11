module "this" {
  source  = "git::https://github.com/cloudposse/terraform-null-label.git?ref=58e273e1721a5a3d18a53cb0bc333b8daef7a819"

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

module "security_hub" {
  count   = local.create_securityhub ? 1 : 0
  source  = "git::https://github.com/cloudposse/terraform-aws-security-hub.git?ref=d394a3b0b4a95cbe5f3c8d7a6e6b3d8c1f2e5a6b"

  cloudwatch_event_rule_pattern_detail_type = var.cloudwatch_event_rule_pattern_detail_type
  create_sns_topic                          = local.create_sns_topic
  enable_default_standards                  = var.default_standards_enabled
  enabled_standards                         = var.enabled_standards
  finding_aggregator_enabled                = local.is_finding_aggregation_region
  finding_aggregator_linking_mode           = var.finding_aggregator_linking_mode
  finding_aggregator_regions                = var.finding_aggregator_regions
  imported_findings_notification_arn        = var.findings_notification_arn
  subscribers                               = var.subscribers

  context = module.this.context
}

module "account_map" {
  source  = "git::https://github.com/cloudposse/terraform-aws-stack-config.git//modules/remote-state?ref=a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6q7r8s9t0"

  component   = "account-map"
  tenant      = var.account_map_tenant != "" ? var.account_map_tenant : module.this.tenant
  stage       = var.root_account_stage
  environment = var.global_environment
  privileged  = var.privileged

  context = module.this.context
}