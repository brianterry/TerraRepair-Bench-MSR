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

module "security_hub" {
  count   = local.create_securityhub? 1 : 0
  source  = "cloudposse/security-hub/aws//modules/security-hub"
  version = "0.10.0"

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
  source  = "cloudposse/stack-config/yaml//modules/remote-state"
  version = "1.5.0"

  component   = "account-map"
  tenant      = var.account_map_tenant!= ""? var.account_map_tenant : module.this.tenant
  stage       = var.root_account_stage
  environment = var.global_environment
  privileged  = var.privileged

  context = module.this.context
}