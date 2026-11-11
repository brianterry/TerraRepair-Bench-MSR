module "this" {
  source  = "git::https://github.com/cloudposse/terraform-null-label.git?ref=58c525e7d58fd9c0b5703c722755f9d39c9f4d1a"
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

data "aws_iam_policy_document" "support_access_trusted_advisor" {
  count = local.support_policy_enabled ? 1 : 0

  statement {
    sid    = "AllowTrustedAdvisor"
    effect = "Allow"
    actions = [
      "trustedadvisor:Describe*",
    ]
  }
}

module "sso" {
  source  = "git::https://github.com/cloudposse/terraform-stack-config-yaml.git?ref=a6d2850c34d0e1eaa1a9b7f0a6d8c3e4f5b6a7d8"
  version = "0.22.2"

  component   = "sso"
  environment = var.sso_environment_name
  stage       = var.sso_stage_name
  privileged  = true

  context = module.this.context
}

module "account_map" {
  source  = "git::https://github.com/cloudposse/terraform-stack-config-yaml.git?ref=a6d2850c34d0e1eaa1a9b7f0a6d8c3e4f5b6a7d8"
  version = "0.22.2"

  component   = "account-map"
  environment = var.account_map_environment_name
  stage       = var.account_map_stage_name
  privileged  = true

  context = module.this.context
}