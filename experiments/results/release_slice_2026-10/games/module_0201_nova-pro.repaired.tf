resource "aws_acm_certificate" "this" {
  provider          = "aws.us_east_1"
  domain_name       = "${var.site_domain}"
  validation_method = "DNS"
  tags              = "${merge(var.tags, map("Name", "${var.comment_prefix}${var.site_domain}"))}"
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_cloudfront_distribution" "this" {
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "${var.default_root_object}"
  aliases             = ["${var.site_domain}"]
  price_class         = "PriceClass_${var.cloudfront_price_class}"
  comment             = "${var.comment_prefix}${var.site_domain}"
  tags                = "${var.tags}"

  origin {
    domain_name = "${local.url_hostname}"
    origin_id   = "default"
    origin_path = "${local.url_path == ""? "" : "/${local.url_path}"}"

    custom_origin_config {
      http_port              = "${var.origin_custom_port > 0? "${var.origin_custom_port}" : 80}"
      https_port             = "${var.origin_custom_port > 0? "${var.origin_custom_port}" : 443}"
      origin_protocol_policy = "${local.url_protocol}-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }

    custom_header {
      name  = "${var.origin_custom_header_name}"
      value = "${var.origin_custom_header_value}"
    }
  }

  default_cache_behavior {
    allowed_methods        = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "default"
    viewer_protocol_policy = "${var.viewer_https_only? "redirect-to-https" : "allow-all"}"
    compress               = true

    min_ttl     = "${var.cache_ttl_override >= 0? var.cache_ttl_override : 0}"
    default_ttl = "${var.cache_ttl_override >= 0? var.cache_ttl_override : 0}"
    max_ttl     = "${var.cache_ttl_override >= 0? var.cache_ttl_override : 86400}"

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
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = "${aws_acm_certificate_validation.this.certificate_arn}"
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2018"
  }

  web_acl_id = "${aws_wafv2_web_acl.this.id}"

  logging_config {
    bucket = "${aws_s3_bucket.logs.bucket}"
    include_cookies = false
    prefix = "cloudfront-logs/"
  }
}

resource "aws_wafv2_web_acl" "this" {
  name        = "cloudfront-waf"
  scope       = "CLOUDFRONT"
  default_action {
    allow {}
  }
  rule {
    name     = "log4j-rule"
    priority = 1
    action {
      allow {}
    }
    statement {
      managed_rule_group {
        name    = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }
  }
  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "cloudfront-waf-metrics"
    sampled_requests_enabled   = true
  }
}

resource "aws_s3_bucket" "logs" {
  bucket = "cloudfront-logs-${var.site_domain}"
  acl    = "private"

  versioning {
    enabled = true
  }

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  }
}

resource "aws_lambda_function" "viewer_request" {
  provider = "aws.us_east_1"

  filename = "${substr(data.archive_file.lambda_zip.output_path, length(path.cwd) + 1, -1)}"

  source_code_hash = "${data.archive_file.lambda_zip.output_base64sha256}"
  function_name    = "${local.prefix_with_domain}---viewer_request"
  role             = "${aws_iam_role.this.arn}"
  description      = "${var.comment_prefix}${var.site_domain} (request handler)"
  handler          = "lambda.viewer_request"
  runtime          = "nodejs14.x"
  publish          = true
  tags             = "${var.tags}"

  tracing_config {
    mode = "Active"
  }
}

resource "aws_lambda_function" "viewer_response" {
  provider = "aws.us_east_1"

  filename = "${substr(data.archive_file.lambda_zip.output_path, length(path.cwd) + 1, -1)}"

  source_code_hash = "${data.archive_file.lambda_zip.output_base64sha256}"
  function_name    = "${local.prefix_with_domain}---viewer_response"
  role             = "${aws_iam_role.this.arn}"
  description      = "${var.comment_prefix}${var.site_domain} (response handler)"
  handler          = "lambda.viewer_response"
  runtime          = "nodejs14.x"
  publish          = true
  tags             = "${var.tags}"

  tracing_config {
    mode = "Active"
  }
}