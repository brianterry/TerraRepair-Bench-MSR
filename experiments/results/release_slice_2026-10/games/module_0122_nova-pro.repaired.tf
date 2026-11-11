locals {
  webhook_endpoint = "webhook"
  role_path        = var.role_path == null? "/${var.prefix}/" : var.role_path
}

resource "aws_apigatewayv2_api" "webhook" {
  name          = "${var.prefix}-github-action-webhook"
  protocol_type = "HTTP"
  tags          = var.tags
}

resource "aws_apigatewayv2_route" "webhook" {
  api_id    = aws_apigatewayv2_api.webhook.id
  route_key = "POST /${local.webhook_endpoint}"
  target    = "integrations/${aws_apigatewayv2_integration.webhook.id}"
  authorization_type = "NONE"
}

resource "aws_apigatewayv2_stage" "webhook" {
  api_id      = aws_apigatewayv2_api.webhook.id
  name        = "$default"
  auto_deploy = true

  access_log_settings {
    destination_arn = var.webhook_lambda_apigateway_access_log_settings.destination_arn
    format          = var.webhook_lambda_apigateway_access_log_settings.format
  }

  tags = var.tags
}

resource "aws_apigatewayv2_integration" "webhook" {
  api_id           = aws_apigatewayv2_api.webhook.id
  integration_type = "AWS_PROXY"

  connection_type    = "INTERNET"
  description        = "GitHub App webhook for receiving build events."
  integration_method = "POST"
  integration_uri    = !var.eventbridge.enable? module.direct[0].webhook.lambda.invoke_arn : module.eventbridge[0].webhook.lambda.invoke_arn
}

output "gateway" {
  value = aws_apigatewayv2_api.webhook
}

output "endpoint_relative_path" {
  value = local.webhook_endpoint
}

output "webhook" {
  value = !var.eventbridge.enable? module.direct[0].webhook : module.eventbridge[0].webhook
}

output "dispatcher" {
  value = var.eventbridge.enable? module.eventbridge[0].dispatcher : null
}

output "eventbridge" {
  value = var.eventbridge.enable? module.eventbridge[0].eventbridge : null
}

output "lambda" {
  value = !var.eventbridge.enable? module.direct[0].webhook.lambda : module.eventbridge[0].webhook.lambda
}

output "lambda_log_group" {
  value = !var.eventbridge.enable? module.direct[0].webhook.log_group : module.eventbridge[0].webhook.log_group
}

output "role" {
  value =!var.eventbridge.enable? module.direct[0].webhook.role : module.eventbridge[0].webhook.role
}

resource "aws_ssm_parameter" "runner_matcher_config" {
  name  = "${var.ssm_paths.root}/${var.ssm_paths.webhook}/runner-matcher-config"
  type  = "String"
  value = jsonencode(local.runner_matcher_config_sorted)
  tier  = var.matcher_config_parameter_store_tier
  kms_key_id = var.kms_key_arn
}