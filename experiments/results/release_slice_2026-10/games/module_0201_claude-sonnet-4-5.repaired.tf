resource "aws_acm_certificate" "this" {
  provider          = "aws.us_east_1"
  domain_name       = "${var.site_domain}"
  validation_method = "DNS"
  tags              = "${merge(var.tags, map("Name", "${var.comment_prefix}${var.site_domain}"))}"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "cert_validation" {
  name    = "${aws_acm_certificate.this.domain_validation_options.0.resource_record_name}"
  type    = "${aws_acm_certificate.this.domain_validation_options.0.resource_record_type}"
  zone_id = "${data.aws_route53_zone.this.zone_id}"
  records = ["${aws_acm_certificate.this.domain_validation_options.0.resource_record_value}"]
  ttl     = 60
}

resource "aws_acm_certificate_validation" "this" {
  provider                = "aws.us_east_1"
  certificate_arn         = "${aws_acm_certificate.this.arn}"
  validation_record_fqdns = ["${aws_route53_record.cert_validation.fqdn}"]
}

resource "aws_wafv2_web_acl" "this" {
  provider    = "aws.us_east_1"
  name        = "${local.prefix_with_domain}"
  description = "${var.comment_prefix}${var.site_domain}"
  scope       = "CLOUDFRONT"

  default_action {
    allow {}
  }

  rule {
    name     = "AWSManagedRulesKnownBadInputsRuleSet"
    priority = 1

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWSManagedRulesKnownBadInputsRuleSetMetric"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${local.prefix_with_domain}"
    sampled_requests_enabled   = true
  }

  tags = "${var.tags}"
}

resource "aws_s3_bucket" "cloudfront_logs" {
  bucket = "${local.prefix_with_domain}-logs"
  tags   = "${var.tags}"
}

resource "aws_s3_bucket_ownership_controls" "cloudfront_logs" {
  bucket = "${aws_s3_bucket.cloudfront_logs.id}"

  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_acl" "cloudfront_logs" {
  depends_on = ["aws_s3_bucket_ownership_controls.cloudfront_logs"]
  bucket     = "${aws_s3_bucket.cloudfront_logs.id}"
  acl        = "private"
}

resource "aws_cloudfront_response_headers_policy" "this" {
  name = "${local.prefix_with_domain}"

  security_headers_config {
    strict_transport_security {
      access_control_max_age_sec = 31557600
      include_subdomains         = true
      preload                    = true
      override                   = true
    }
  }
}

resource "aws_cloudfront_distribution" "this" {
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  aliases             = ["${var.site_domain}"]
  price_class         = "PriceClass_${var.cloudfront_price_class}"
  comment             = "${var.comment_prefix}${var.site_domain}"
  tags                = "${var.tags}"
  web_acl_id          = "${aws_wafv2_web_acl.this.arn}"

  logging_config {
    include_cookies = false
    bucket          = "${aws_s3_bucket.cloudfront_logs.bucket_domain_name}"
    prefix          = "cloudfront/"
  }

  origin_group {
    origin_id = "default"

    failover_criteria {
      status_codes = [403, 404, 500, 502, 503, 504]
    }

    member {
      origin_id = "primary"
    }

    member {
      origin_id = "secondary"
    }
  }

  origin {
    domain_name = "${local.url_hostname}"
    origin_id   = "primary"
    origin_path = "${local.url_path == "" ? "" : "/${local.url_path}"}"

    custom_origin_config {
      http_port              = "${var.origin_custom_port > 0 ? "${var.origin_custom_port}" : 80}"
      https_port             = "${var.origin_custom_port > 0 ? "${var.origin_custom_port}" : 443}"
      origin_protocol_policy = "${local.url_protocol}-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }

    custom_header {
      name  = "${var.origin_custom_header_name}"
      value = "${var.origin_custom_header_value}"
    }
  }

  origin {
    domain_name = "${local.url_hostname}"
    origin_id   = "secondary"
    origin_path = "${local.url_path == "" ? "" : "/${local.url_path}"}"

    custom_origin_config {
      http_port              = "${var.origin_custom_port > 0 ? "${var.origin_custom_port}" : 80}"
      https_port             = "${var.origin_custom_port > 0 ? "${var.origin_custom_port}" : 443}"
      origin_protocol_policy = "${local.url_protocol}-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }

    custom_header {
      name  = "${var.origin_custom_header_name}"
      value = "${var.origin_custom_header_value}"
    }
  }

  default_cache_behavior {
    allowed_methods              = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods               = ["GET", "HEAD"]
    target_origin_id             = "default"
    viewer_protocol_policy       = "${var.viewer_https_only ? "redirect-to-https" : "allow-all"}"
    compress                     = true
    response_headers_policy_id   = "${aws_cloudfront_response_headers_policy.this.id}"

    min_ttl     = "${var.cache_ttl_override >= 0 ? var.cache_ttl_override : 0}"
    default_ttl = "${var.cache_ttl_override >= 0 ? var.cache_ttl_override : 0}"
    max_ttl     = "${var.cache_ttl_override >= 0 ? var.cache_ttl_override : 86400}"

    forwarded_values {
      query_string = true

      cookies {
        forward = "all"
      }
    }

    lambda_function_association {
      event_type = "viewer-request"
      lambda_arn = "${aws_lambda_function.viewer_request.arn}:${aws_lambda_function.viewer_request.version}"
    }

    lambda_function_association {
      event_type = "viewer-response"
      lambda_arn = "${aws_lambda_function.viewer_response.arn}:${aws_lambda_function.viewer_response.version}"
    }
  }

  custom_error_response {
    error_code            = 400
    error_caching_min_ttl = "${local.error_ttl}"
  }

  custom_error_response {
    error_code            = 403
    error_caching_min_ttl = "${local.error_ttl}"
  }

  custom_error_response {
    error_code            = 404
    error_caching_min_ttl = "${local.error_ttl}"
  }

  custom_error_response {
    error_code            = 405
    error_caching_min_ttl = "${local.error_ttl}"
  }

  custom_error_response {
    error_code            = 414
    error_caching_min_ttl = "${local.error_ttl}"
  }

  custom_error_response {
    error_code            = 416
    error_caching_min_ttl = "${local.error_ttl}"
  }

  custom_error_response {
    error_code            = 500
    error_caching_min_ttl = "${local.error_ttl}"
  }

  custom_error_response {
    error_code            = 501
    error_caching_min_ttl = "${local.error_ttl}"
  }

  custom_error_response {
    error_code            = 502
    error_caching_min_ttl = "${local.error_ttl}"
  }

  custom_error_response {
    error_code            = 503
    error_caching_min_ttl = "${local.error_ttl}"
  }

  custom_error_response {
    error_code            = 504
    error_caching_min_ttl = "${local.error_ttl}"
  }

  restrictions {
    geo_restriction {
      restriction_type = "whitelist"
      locations        = ["US", "CA", "GB", "DE"]
    }
  }

  viewer_certificate {
    acm_certificate_arn      = "${aws_acm_certificate_validation.this.certificate_arn}"
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }
}

data "aws_route53_zone" "this" {
  name = "${replace("${var.site_domain}", "/.*\\b(\\w+\\.\\w+)\\.?$/", "$1")}"
}

locals {
  config = {
    basic_auth_username                  = "${var.basic_auth_username}"
    basic_auth_password                  = "${var.basic_auth_password}"
    basic_auth_realm                     = "${var.basic_auth_realm}"
    basic_auth_body                      = "${var.basic_auth_body}"
    override_response_status             = "${var.override_response_status}"
    override_response_status_description = "${var.override_response_status_description}"
    override_response_body               = "${var.override_response_body}"
  }
}

data "template_file" "lambda" {
  template = "${file("${path.module}/lambda.tpl.js")}"

  vars = {
    config               = "${jsonencode(local.config)}"
    add_response_headers = "${jsonencode(var.add_response_headers)}"
  }
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/lambda.zip"

  source {
    filename = "lambda.js"
    content  = "${data.template_file.lambda.rendered}"
  }
}

resource "aws_sqs_queue" "lambda_dlq" {
  name = "${local.prefix_with_domain}-dlq"
  tags = "${var.tags}"
}

resource "aws_lambda_code_signing_config" "this" {
  allowed_publishers {
    signing_profile_version_arns = ["${aws_signer_signing_profile.this.arn}"]
  }

  policies {
    untrusted_artifact_on_deployment = "Enforce"
  }
}

resource "aws_signer_signing_profile" "this" {
  platform_id = "AWSLambda-SHA384-ECDSA"
  name        = "${local.prefix_with_domain}"
  tags        = "${var.tags}"
}

resource "aws_security_group" "lambda" {
  name        = "${local.prefix_with_domain}"
  description = "Security group for Lambda functions"
  vpc_id      = "${aws_vpc.lambda.id}"
  tags        = "${var.tags}"

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_vpc" "lambda" {
  cidr_block = "10.0.0.0/16"
  tags       = "${var.tags}"
}

resource "aws_subnet" "lambda" {
  vpc_id     = "${aws_vpc.lambda.id}"
  cidr_block = "10.0.1.0/24"
  tags       = "${var.tags}"
}

resource "aws_lambda_function" "viewer_request" {
  provider         = "aws.us_east_1"
  filename         = "${substr(data.archive_file.lambda_zip.output_path, length(path.cwd) + 1, -1)}"
  source_code_hash = "${data.archive_file.lambda_zip.output_base64sha256}"
  function_name    = "${local.prefix_with_domain}---viewer_request"
  role             = "${aws_iam_role.this.arn}"
  description      = "${var.comment_prefix}${var.site_domain} (request handler)"
  handler          = "lambda.viewer_request"
  runtime          = "nodejs20.x"
  publish          = true
  tags             = "${var.tags}"
  reserved_concurrent_executions = 10
  code_signing_config_arn        = "${aws_lambda_code_signing_config.this.arn}"

  dead_letter_config {
    target_arn = "${aws_sqs_queue.lambda_dlq.arn}"
  }

  tracing_config {
    mode = "Active"
  }

  vpc_config {
    subnet_ids         = ["${aws_subnet.lambda.id}"]
    security_group_ids = ["${aws_security_group.lambda.id}"]
  }
}

resource "aws_lambda_function" "viewer_response" {
  provider         = "aws.us_east_1"
  filename         = "${substr(data.archive_file.lambda_zip.output_path, length(path.cwd) + 1, -1)}"
  source_code_hash = "${data.archive_file.lambda_zip.output_base64sha256}"
  function_name    = "${local.prefix_with_domain}---viewer_response"
  role             = "${aws_iam_role.this.arn}"
  description      = "${var.comment_prefix}${var.site_domain} (response handler)"
  handler          = "lambda.viewer_response"
  runtime          = "nodejs20.x"
  publish          = true
  tags             = "${var.tags}"
  reserved_concurrent_executions = 10
  code_signing_config_arn        = "${aws_lambda_code_signing_config.this.arn}"

  dead_letter_config {
    target_arn = "${aws_sqs_queue.lambda_dlq.arn}"
  }

  tracing_config {
    mode = "Active"
  }

  vpc_config {
    subnet_ids         = ["${aws_subnet.lambda.id}"]
    security_group_ids = ["${aws_security_group.lambda.id}"]
  }
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

resource "aws_iam_policy" "this" {
  count = "${var.lambda_logging_enabled ? 1 : 0}"
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
  count      = "${var.lambda_logging_enabled ? 1 : 0}"
  role       = "${aws_iam_role.this.name}"
  policy_arn = "${aws_iam_policy.this.arn}"
}

resource "aws_iam_role_policy_attachment" "lambda_vpc_execution" {
  role       = "${aws_iam_role.this.name}"
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy_attachment" "lambda_xray" {
  role       = "${aws_iam_role.this.name}"
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

resource "aws_iam_role_policy" "lambda_sqs" {
  name = "${local.prefix_with_domain}-sqs"
  role = "${aws_iam_role.this.id}"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "sqs:SendMessage"
      ],
      "Resource": "${aws_sqs_queue.lambda_dlq.arn}"
    }
  ]
}
EOF
}

output "cloudfront_id" {
  description = "The ID of the CloudFront distribution that's used for hosting the content"
  value       = "${aws_cloudfront_distribution.this.id}"
}

output "site_domain" {
  description = "Domain on which the site will be made available"
  value       = "${var.site_domain}"
}

resource "aws_route53_record" "ipv4" {
  zone_id = "${data.aws_route53_zone.this.zone_id}"
  name    = "${var.site_domain}"
  type    = "A"

  alias {
    name                   = "${aws_cloudfront_distribution.this.domain_name}"
    zone_id                = "${aws_cloudfront_distribution.this.hosted_zone_id}"
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "ipv6" {
  zone_id = "${data.aws_route53_zone.this.zone_id}"
  name    = "${var.site_domain}"
  type    = "AAAA"

  alias {
    name                   = "${aws_cloudfront_distribution.this.domain_name}"
    zone_id                = "${aws_cloudfront_distribution.this.hosted_zone_id}"
    evaluate_target_health = false
  }
}

variable "site_domain" {
  description = "Domain on which the reverse proxy will be made available (e.g. `\"www.example.com\"`)"
}

variable "name_prefix" {
  description = "Name prefix to use for objects that need to be created (only lowercase alphanumeric characters and hyphens allowed, for S3 bucket name compatibility)"
  default     = "aws-reverse-proxy---"
}

variable "comment_prefix" {
  description = "This will be included in comments for resources that are created"
  default     = "Reverse proxy: "
}

variable "origin_url" {
  description = "Base URL for proxy upstream site (e.g. `\"https://example.com/\"`)"
}

variable "cloudfront_price_class" {
  description = "CloudFront price class to use (`100`, `200` or `\"All\"`, see https://aws.amazon.com/cloudfront/pricing/)"
  default     = 100
}

variable "viewer_https_only" {
  description = "Set this to `false` if you need to support insecure HTTP access for clients, in addition to HTTPS"
  default     = true
}

variable "cache_ttl_override" {
  description = "When >= 0, override the cache behaviour for ALL objects in the origin, so that they stay in the CloudFront cache for this amount of seconds"
  default     = -1
}

variable "default_root_object" {
  description = "The object to return when the root URL is requested"
  default     = ""
}

variable "add_response_headers" {
  description = "Map of HTTP headers (if any) to add to outgoing responses before sending them to clients"
  type        = "map"

  default = {
    "Strict-Transport-Security" = "max-age=31557600; preload"
  }
}

variable "origin_custom_header_name" {
  description = "Name of a custom header to send to the origin; this can be used to convey an authentication header to the origin, for example"
  default     = "X-Custom-Origin-Header"
}

variable "origin_custom_header_value" {
  description = "Value of a custom header to send to the origin; see `origin_custom_header_name`"
  default     = ""
}

variable "origin_custom_port" {
  description = "When > 0, use this port for communication with the origin server, instead of relevant standard port"
  default     = 0
}

variable "override_response_status" {
  description = "When this and the other `override_response_*` variables are non-empty, skip sending the request to the origin altogether, and instead respond as instructed here"
  default     = ""
}

variable "override_response_status_description" {
  description = "Same as `override_response_status`"
  default     = ""
}

variable "override_response_body" {
  description = "Same as `override_response_status`"
  default     = ""
}

variable "basic_auth_username" {
  description = "When non-empty, require this username with HTTP Basic Auth"
  default     = ""
}

variable "basic_auth_password" {
  description = "When non-empty, require this password with HTTP Basic Auth"
  default     = ""
}

variable "basic_auth_realm" {
  description = "When using HTTP Basic Auth, this will be displayed by the browser in the auth prompt"
  default     = "Authentication Required"
}

variable "basic_auth_body" {
  description = "When using HTTP Basic Auth, and authentication has failed, this will be displayed by the browser as the page content"
  default     = "Unauthorized"
}

variable "lambda_logging_enabled" {
  description = "When true, writes information about incoming requests to the Lambda function's CloudWatch group"
  default     = false
}

variable "tags" {
  description = "AWS Tags to add to all resources created (where possible); see https://aws.amazon.com/answers/account-management/aws-tagging-strategies/"
  type        = "map"
  default     = {}
}

locals {
  prefix_with_domain = "${var.name_prefix}${replace("${var.site_domain}", "/[^a-z0-9-]+/", "-")}"
  error_ttl          = "${var.cache_ttl_override >= 0 ? var.cache_ttl_override : 0}"
}

locals {
  url_protocol = "${replace("${var.origin_url}", "/^(?:(\\w+):\\/\\/).*/", "$1")}"
  url_hostname = "${replace("${var.origin_url}", "/^(?:\\w+:\\/\\/)?([^/]+).*/", "$1")}"
  url_path     = "${replace("${var.origin_url}", "/^(?:\\w+:\\/\\/)?[^/]+(?:\\/(.*)|$)/", "$1")}"
}