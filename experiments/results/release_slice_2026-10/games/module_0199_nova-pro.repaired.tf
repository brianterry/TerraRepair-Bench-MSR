resource "aws_api_gateway_rest_api" "this" {
  name        = "${local.prefix_with_domain}"
  description = "${var.comment_prefix}${var.api_domain}"
  create_before_destroy = true
}

resource "aws_api_gateway_deployment" "this" {
  rest_api_id = "${aws_api_gateway_rest_api.this.id}"
  create_before_destroy = true

  depends_on = [
    "aws_api_gateway_integration.proxy_root",
    "aws_api_gateway_integration.proxy_other",
  ]
}

resource "aws_api_gateway_stage" "this" {
  stage_name    = "${var.stage_name}"
  description   = "${var.comment_prefix}${var.api_domain}"
  rest_api_id   = "${aws_api_gateway_rest_api.this.id}"
  deployment_id = "${aws_api_gateway_deployment.this.id}"
  tags          = "${var.tags}"
  access_log_settings {
    destination_arn = "${aws_iam_role.this.arn}"
    format = "$context.requestId"
  }
  tracing_enabled = true
  cache_cluster_enabled = true
  cache_cluster_size = "0.5"
  method_settings {
    metrics_enabled = true
    logging_level = "INFO"
    data_trace_enabled = true
  }
}

resource "aws_api_gateway_method_settings" "this" {
  rest_api_id = "${aws_api_gateway_rest_api.this.id}"
  stage_name  = "${aws_api_gateway_stage.this.stage_name}"
  method_path = "*/*"

  settings {
    metrics_enabled        = true
    logging_level          = "INFO"
    data_trace_enabled     = true
    caching_enabled        = true
    cache_ttl_in_seconds   = 300
    throttling_rate_limit  = "${var.throttling_rate_limit}"
    throttling_burst_limit = "${var.throttling_burst_limit}"
  }
}

resource "aws_api_gateway_domain_name" "this" {
  domain_name              = "${var.api_domain}"
  regional_certificate_arn = "${aws_acm_certificate_validation.this.certificate_arn}"
  security_policy          = "TLS_1_2"

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

resource "aws_api_gateway_base_path_mapping" "this" {
  api_id      = "${aws_api_gateway_rest_api.this.id}"
  stage_name  = "${aws_api_gateway_stage.this.stage_name}"
  domain_name = "${aws_api_gateway_domain_name.this.domain_name}"
}

resource "aws_api_gateway_method" "proxy_root" {
  rest_api_id   = "${aws_api_gateway_rest_api.this.id}"
  resource_id   = "${aws_api_gateway_rest_api.this.root_resource_id}"
  http_method   = "ANY"
  authorization = "NONE"
  request_models = {
    "application/json" = "Empty"
  }
}

resource "aws_api_gateway_integration" "proxy_root" {
  rest_api_id             = "${aws_api_gateway_rest_api.this.id}"
  resource_id             = "${aws_api_gateway_method.proxy_root.resource_id}"
  http_method             = "${aws_api_gateway_method.proxy_root.http_method}"
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = "${local.function_invoke_arn}"
}

resource "aws_api_gateway_resource" "proxy_other" {
  rest_api_id = "${aws_api_gateway_rest_api.this.id}"
  parent_id   = "${aws_api_gateway_rest_api.this.root_resource_id}"
  path_part   = "{proxy+}"
}

resource "aws_api_gateway_method" "proxy_other" {
  rest_api_id   = "${aws_api_gateway_rest_api.this.id}"
  resource_id   = "${aws_api_gateway_resource.proxy_other.id}"
  http_method   = "ANY"
  authorization = "NONE"
  request_models = {
    "application/json" = "Empty"
  }
}

resource "aws_api_gateway_integration" "proxy_other" {
  rest_api_id             = "${aws_api_gateway_rest_api.this.id}"
  resource_id             = "${aws_api_gateway_method.proxy_other.resource_id}"
  http_method             = "${aws_api_gateway_method.proxy_other.http_method}"
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = "${local.function_invoke_arn}"
}

resource "aws_api_gateway_method_response" "proxy_other" {
  rest_api_id = "${aws_api_gateway_rest_api.this.id}"
  resource_id = "${aws_api_gateway_resource.proxy_other.id}"
  http_method = "${aws_api_gateway_method.proxy_other.http_method}"
  status_code = "200"

  response_models = {
    "application/json" = "Empty"
  }
}

resource "aws_api_gateway_integration_response" "proxy_other" {
  depends_on  = ["aws_api_gateway_integration.proxy_other"]
  rest_api_id = "${aws_api_gateway_rest_api.this.id}"
  resource_id = "${aws_api_gateway_resource.proxy_other.id}"
  http_method = "${aws_api_gateway_method.proxy_other.http_method}"
  status_code = "${aws_api_gateway_method_response.proxy_other.status_code}"

  response_templates = {
    "application/json" = ""
  }
}

resource "aws_acm_certificate" "this" {
  domain_name       = "${var.api_domain}"
  validation_method = "DNS"
  create_before_destroy = true
  tags              = "${merge(var.tags, map("Name", "${var.comment_prefix}${var.api_domain}"))}"
}

resource "aws_route53_record" "cert_validation" {
  name    = "${aws_acm_certificate.this.domain_validation_options.0.resource_record_name}"
  type    = "${aws_acm_certificate.this.domain_validation_options.0.resource_record_type}"
  zone_id = "${data.aws_route53_zone.this.zone_id}"
  records = ["${aws_acm_certificate.this.domain_validation_options.0.resource_record_value}"]
  ttl     = 60
}

resource "aws_acm_certificate_validation" "this" {
  certificate_arn         = "${aws_acm_certificate.this.arn}"
  validation_record_fqdns = ["${aws_route53_record.cert_validation.fqdn}"]
}

data "aws_route53_zone" "this" {
  name = "${replace("${var.api_domain}", "/.*\\b(\\w+\\.\\w+)\\.?$/", "$1")}"
}

resource "aws_lambda_function" "local_zipfile" {
  count = "${var.function_s3_bucket == ""? 1 : 0}"

  filename         = "${var.function_zipfile}"
  source_code_hash = "${var.function_s3_bucket == ""? "${base64sha256(file("${var.function_zipfile}"))}" : ""}"
  description   = "${var.comment_prefix}${var.api_domain}"
  function_name = "${local.prefix_with_domain}"
  handler       = "${var.function_handler}"
  runtime       = "${var.function_runtime}"
  timeout       = "${var.function_timeout}"
  memory_size   = "${var.memory_size}"
  role          = "${aws_iam_role.this.arn}"
  tags          = "${var.tags}"
  tracing_config {
    mode = "Active"
  }

  environment {
    variables = "${var.function_env_vars}"
  }
}

resource "aws_lambda_function" "s3_zipfile" {
  count = "${var.function_s3_bucket == ""? 0 : 1}"

  s3_bucket = "${var.function_s3_bucket}"
  s3_key    = "${var.function_zipfile}"
  description   = "${var.comment_prefix}${var.api_domain}"
  function_name = "${local.prefix_with_domain}"
  handler       = "${var.function_handler}"
  runtime       = "${var.function_runtime}"
  timeout       = "${var.function_timeout}"
  memory_size   = "${var.memory_size}"
  role          = "${aws_iam_role.this.arn}"
  tags          = "${var.tags}"
  tracing_config {
    mode = "Active"
  }

  environment {
    variables = "${var.function_env_vars}"
  }
}

locals {
  function_id         = "${element(concat(aws_lambda_function.local_zipfile.*.id, list("")), 0)}${element(concat(aws_lambda_function.s3_zipfile.*.id, list("")), 0)}"
  function_arn        = "${element(concat(aws_lambda_function.local_zipfile.*.arn, list("")), 0)}${element(concat(aws_lambda_function.s3_zipfile.*.arn, list("")), 0)}"
  function_invoke_arn = "${element(concat(aws_lambda_function.local_zipfile.*.invoke_arn, list("")), 0)}${element(concat(aws_lambda_function.s3_zipfile.*.invoke_arn, list("")), 0)}"
}

output "function_name" {
  description = "This is the unique name of the Lambda function that was created"
  value       = "${local.function_id}"
}

output "api_gw_invoke_url" {
  description = "This URL can be used to invoke the Lambda through the API Gateway"
  value       = "${aws_api_gateway_deployment.this.invoke_url}"
}

resource "aws_iam_role" "this" {
  name = "${local.prefix_with_domain}"
  tags = "${var.tags}"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": [
          "lambda.amazonaws.com",
          "edgelambda.amazonaws.com"
        ]
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_lambda_permission" "this" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = "${local.function_arn}"
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_stage.this.execution_arn}/*/*"
}

resource "aws_iam_policy" "this" {
  count = "${var.lambda_logging_enabled? 1 : 0}"
  name  = "${local.prefix_with_domain}"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "arn:aws:logs:*:*:*",
      "Effect": "Allow"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "this" {
  count      = "${var.lambda_logging_enabled? 1 : 0}"
  role       = "${aws_iam_role.this.name}"
  policy_arn = "${aws_iam_policy.this.arn}"
}

resource "aws_route53_record" "ipv4" {
  zone_id = "${data.aws_route53_zone.this.zone_id}"
  name    = "${var.api_domain}"
  type    = "A"

  alias {
    name                   = "${aws_api_gateway_domain_name.this.regional_domain_name}"
    zone_id                = "${aws_api_gateway_domain_name.this.regional_zone_id}"
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "ipv6" {
  zone_id = "${data.aws_route53_zone.this.zone_id}"
  name    = "${var.api_domain}"
  type    = "AAAA"

  alias {
    name                   = "${aws_api_gateway_domain_name.this.regional_domain_name}"
    zone_id                = "${aws_api_gateway_domain_name.this.regional_zone_id}"
    evaluate_target_health = false
  }
}