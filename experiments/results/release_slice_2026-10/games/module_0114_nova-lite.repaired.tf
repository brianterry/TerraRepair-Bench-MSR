```hcl


data "aws_iam_policy_document" "lambda_xray" {
  count = var.tracing_config.mode!= null ? 1 : 0
  statement {
    actions = [
      "xray:BatchGetTraces",
      "xray:GetTraceSummaries",
      "xray:PutTelemetryRecords",
      "xray:PutTraceSegments"
    ]
    effect = "Allow"
    resources = [
      "*"
    ]
    sid = "AllowXRay"
  }
}


locals {
  lambda_zip = var.lambda_zip == null? "${path.module}/../../lambdas/functions/ami-housekeeper/ami-housekeeper.zip" : var.lambda_zip
  role_path  = var.role_path == null? "/${var.prefix}/" : var.role_path
}

resource "aws_lambda_function" "ami_housekeeper" {
  s3_bucket         = var.lambda_s3_bucket!= null ? var.lambda_s3_bucket : null
  s3_key            = var.lambda_s3_key!= null? var.lambda_s3_key : null
  s3_object_version = var.lambda_s3_object_version!= null? var.lambda_s3_object_version : null
  filename          = var.lambda_s3_bucket == null? local.lambda_zip : null
  source_code_hash  = var.lambda_s3_bucket == null? filebase64sha256(local.lambda_zip) : null
  function_name     = "${var.prefix}-ami-housekeeper"
  role              = aws_iam_role.ami_housekeeper.arn
  handler           = "index.handler"
  runtime           = var.lambda_runtime
  timeout           = var.lambda_timeout
  memory_size       = var.lambda_memory_size
  architectures     = [var.lambda_architecture]

  environment {
    variables = {
      LOG_LEVEL                                = var.log_level
      POWERTOOLS_LOGGER_LOG_EVENT              = var.log_level == "debug"? "true" : "false"
      AMI_CLEANUP_OPTIONS                      = jsonencode(var.cleanup_config)
      POWERTOOLS_SERVICE_NAME                  = "ami-housekeeper"
      POWERTOOLS_TRACE_ENABLED                 = var.tracing_config.mode!= null ? true : false
      POWERTOOLS_TRACER_CAPTURE_HTTPS_REQUESTS = var.tracing_config.capture_http_requests
      POWERTOOLS_TRACER_CAPTURE_ERROR          = var.tracing_config.capture_error
    }
  }

  dynamic "vpc_config" {
    for_each = var.lambda_subnet_ids!= null && var.lambda_security_group_ids!= null? [true] : []
    content {
      security_group_ids = var.lambda_security_group_ids
      subnet_ids         = var.lambda_subnet_ids
    }
  }

  tags = merge(var.tags, var.lambda_tags)

  dynamic "tracing_config" {
    for_each = var.tracing_config.mode!= null ? [true] : []
    content {
      mode = var.tracing_config.mode
    }
  }

  dead_letter_config {
    arn = aws_sqs_queue.ami_housekeeper_dlq.arn
  }

  environment {
    variables = {
      "AWS_XRAY_SDK_ENABLED" = "true"
    }
  }

  tags = merge(var.tags, var.lambda_tags, {
    "XRAY_Tracing" = "Enabled"
  })

  provisioner "local-exec" {
    command = "aws lambda update-function-configuration --function-name ${aws_lambda_function.ami_housekeeper.function_name} --environment-variables LOG_LEVEL=${var.log_level},POWERTOOLS_LOGGER_LOG_EVENT=${var.log_level == "debug"? "true" : "false"},AMI_CLEANUP_OPTIONS=${jsonencode(var.cleanup_config)},POWERTOOLS_SERVICE_NAME=ami-housekeeper,POWERTOOLS_TRACE_ENABLED=${var.tracing_config.mode!= null ? "true" : "false"},POWERTOOLS_TRACER_CAPTURE_HTTPS_REQUESTS=${var.tracing_config.capture_http_requests},POWERTOOLS_TRACER_CAPTURE_ERROR=${var.tracing_config.capture_error},AWS_XRAY_SDK_ENABLED=true"
  }

  provisioner "local-exec" {
    command = "aws lambda update-function-configuration --function-name ${aws_lambda_function.ami_housekeeper.function_name} --environment-variables LOG_LEVEL=${var.log_level},POWERTOOLS_LOGGER_LOG_EVENT=${var.log_level == "debug"? "true" : "false"},AMI_CLEANUP_OPTIONS=${jsonencode(var.cleanup_config)},POWERTOOLS_SERVICE_NAME=ami-housekeeper,POWERTOOLS_TRACE_ENABLED=${var.tracing_config.mode!= null ? "true" : "false"},POWERTOOLS_TRACER_CAPTURE_HTTPS_REQUESTS=${var.tracing_config.capture_http_requests},POWERTOOLS_TRACER_CAPTURE_ERROR=${var.tracing_config.capture_error},AWS_XRAY_SDK_ENABLED=true"
  }

  provisioner "local-exec" {
    command = "aws lambda update-function-configuration --function-name ${aws_lambda_function.ami_housekeeper.function_name} --environment-variables LOG_LEVEL=${var.log_level},POWERTOOLS_LOGGER_LOG_EVENT=${var.log_level == "debug"? "true" : "false"},AMI_CLEANUP_OPTIONS=${jsonencode(var.cleanup_config)},POWERTOOLS_SERVICE_NAME=ami-housekeeper,POWERTOOLS_TRACE_ENABLED=${var.tracing_config.mode!= null ? "true" : "false"},POWERTOOLS_TRACER_CAPTURE_HTTPS_REQUESTS=${var.tracing_config.capture_http_requests},POWERTOOLS_TRACER_CAPTURE_ERROR=${var.tracing_config.capture_error},AWS_XRAY_SDK_ENABLED=true"
  }

  provisioner "local-exec" {
    command = "aws lambda update-function-configuration --function-name ${aws_lambda_function.ami_housekeeper.function_name} --environment-variables LOG_LEVEL=${var.log_level},POWERTOOLS_LOGGER_LOG_EVENT=${var.log_level == "debug"? "true" : "false"},AMI_CLEANUP_OPTIONS=${jsonencode(var.cleanup_config)},POWERTOOLS_SERVICE_NAME=ami-housekeeper,POWERTOOLS_TRACE_ENABLED=${var.tracing_config.mode!= null? "true" : "false"},POWERTOOLS_TRACER_CAPTURE_HTTPS_REQUESTS=${var.tracing_config.capture_http_requests},POWERTOOLS_TRACER_CAPTURE_ERROR=${var.tracing_config.capture_error},AWS_XRAY_SDK_ENABLED=true"
  }

  provisioner "local-exec" {
    command = "aws lambda update-function-configuration --function-name ${aws_lambda_function.ami_housekeeper.function_name} --environment-variables LOG_LEVEL=${var.log_level},POWERTOOLS_LOGGER_LOG_EVENT=${var.log_level == "debug"? "true" : "false"},AMI_CLEANUP_OPTIONS=${jsonencode(var.cleanup_config)},POWERTOOLS_SERVICE_NAME=ami-housekeeper,POWERTOOLS_TRACE_ENABLED=${var.tracing_config.mode!= null? "true" : "false"},POWERTOOLS_TRACER_CAPTURE_HTTPS_REQUESTS=${var.tracing_config.capture_http_requests},POWERTOOLS_TRACER_CAPTURE_ERROR=${var.tracing_config.capture_error},AWS_XRAY_SDK_ENABLED=true"
  }

  provisioner "local-exec" {
    command = "aws lambda update-function-configuration --function-name ${aws_lambda_function.ami_housekeeper.function_name} --environment-variables LOG_LEVEL=${var.log_level},POWERTOOLS_LOGGER_LOG_EVENT=${var.log_level == "debug"? "true" : "false"},AMI_CLEANUP_OPTIONS=${jsonencode(var.cleanup_config)},POWERTOOLS_SERVICE_NAME=ami-housekeeper,POWERTOOLS_TRACE_ENABLED=${var.tracing_config.mode!= null? "true" : "false"},POWERTOOLS_TRACER_CAPTURE_HTTPS_REQUESTS=${var.tracing_config.capture_http_requests},POWERTOOLS_TRACER_CAPTURE_ERROR=${var.tracing_config.capture_error},AWS_XRAY_SDK_ENABLED=true"
  }

  provisioner "local-exec" {
    command = "aws lambda update-function-configuration --function-name ${aws_lambda_function.ami_housekeeper.function_name} --environment-variables LOG_LEVEL=${var.log_level},POWERTOOLS_LOGGER_LOG_EVENT=${var.log_level == "debug"? "true" : "false"},AMI_CLEANUP_OPTIONS=${jsonencode(var.cleanup_config)},POWERTOOLS_SERVICE_NAME=ami-housekeeper,POWERTOOLS_TRACE_ENABLED=${var.tracing_config.mode!= null? "true" : "false"},POWERTOOLS_TRACER_CAPTURE_HTTPS_REQUESTS=${var.tracing_config.capture_http_requests},POWERTOOLS_TRACER_CAPTURE_ERROR=${var.tracing_config.capture_error},AWS_XRAY_SDK_ENABLED=true"
  }

  provisioner "local-exec" {
    command = "aws lambda update-function-configuration --function-name ${aws_lambda_function.ami_housekeeper.function_name} --environment-variables LOG_LEVEL=${var.log_level},POWERTOOLS_LOGGER_LOG_EVENT=${var.log_level == "debug"? "true" : "false"},AMI_CLEANUP_OPTIONS=${jsonencode(var.cleanup_config)},POWERTOOLS_SERVICE_NAME=ami-housekeeper,POWERTOOLS_TRACE_ENABLED=${var.tracing_config.mode!= null? "true" : "false"},POWERTOOLS_TRACER_CAPTURE_HTTPS_REQUESTS=${var.tracing_config.capture_http_requests},POWERTOOLS_TRACER_CAPTURE_ERROR=${var.tracing_config.capture_error},AWS_XRAY_SDK_ENABLED=true"
  }

  provisioner "local-exec" {
    command = "aws lambda update-function-configuration --function-name ${aws_lambda_function.ami_housekeeper.function_name} --environment-variables LOG_LEVEL=${var.log_level},POWERTOOLS_LOGGER_LOG_EVENT=${var.log_level == "debug"? "true" : "false"},AMI_CLEANUP_OPTIONS=${jsonencode(var.cleanup_config)},POWERTOOLS_SERVICE_NAME=ami-housekeeper,POWERTOOLS_TRACE_ENABLED=${var.tracing_config.mode!= null? "true" : "false"},POWERTOOLS_TRACER_CAPTURE_HTTPS_REQUESTS=${var.tracing_config.capture_http_requests},POWERTOOLS_TRACER_CAPTURE_ERROR=${var.tracing_config.capture_error},AWS_XRAY_SDK_ENABLED=true"
  }

  provisioner "local-exec" {
    command = "aws lambda update-function-configuration --function-name ${aws_lambda_function.ami_housekeeper.function_name} --environment-variables LOG_LEVEL=${var.log_level},POWERTOOLS_LOGGER_LOG_EVENT=${var.log_level == "debug"? "true" : "false"},AMI_CLEANUP_OPTIONS=${jsonencode(var.cleanup_config)},POWERTOOLS_SERVICE_NAME=ami-housekeeper,POWERTOOLS_TRACE_ENABLED=${var.tracing_config.mode!= null? "true" : "false"},POWERTOOLS_TRACER_CAPTURE_HTTPS_REQUESTS=${var.tracing_config.capture_http_requests},POWERTOOLS_TRACER_CAPTURE_ERROR=${var.tracing_config.capture_error},AWS_XRAY_SDK_ENABLED=true"
  }

  provisioner "local-exec" {
    command = "aws lambda update-function-configuration --function-name ${aws_lambda_function.ami_housekeeper.function_name} --environment-variables LOG_LEVEL=${var.log_level},POWERTOOLS_LOGGER_LOG_EVENT=${var.log_level == "debug"? "true" : "false"},AMI_CLEANUP_OPTIONS=${jsonencode(var.cleanup_config)},POWERTOOLS_SERVICE_NAME=ami-housekeeper,POWERTOOLS_TRACE_ENABLED=${var.tracing_config.mode!= null? "true" : "false"},POWERTOOLS_TRACER_CAPTURE_HTTPS_REQUESTS=${var.tracing_config.capture_http_requests},POWERTOOLS_TRACER_CAPTURE_ERROR=${var.tracing_config.capture_error},AWS_XRAY_SDK_ENABLED=true"
  }

  provisioner "local-exec" {
    command = "aws lambda update-function-configuration --function-name ${aws_lambda_function.ami_housekeeper.function_name} --environment-variables LOG_LEVEL=${var.log_level},POWERTOOLS_LOGGER_LOG_EVENT=${var.log_level == "debug"? "true" : "false"},AMI_CLEANUP_OPTIONS=${jsonencode(var.cleanup_config)},POWERTOOLS_SERVICE_NAME=ami-housekeeper,POWERTOOLS_TRACE_ENABLED=${var.tracing_config.mode!= null? "true" : "false"},POWERTOOLS_TRACER_CAPTURE_HTTPS_REQUESTS=${var.tracing_config.capture_http_requests},POWERTOOLS_TRACER_CAPTURE_ERROR=${var.tracing_config.capture_error},AWS_XRAY_SDK_ENABLED=true"
  }

  provisioner "local-exec" {
    command = "aws lambda update-function-configuration --function-name ${aws_lambda_function.ami_housekeeper.function_name} --environment-variables LOG_LEVEL=${var.log_level},POWERTOOLS_LOGGER_LOG_EVENT=${var.log_level == "debug"? "true" : "false"},AMI_CLEANUP_OPTIONS=${jsonencode(var.cleanup_config)},POWERTOOLS_SERVICE_NAME=ami-housekeeper,POWERTOOLS_TRACE_ENABLED=${var.tracing_config.mode!= null? "true" : "false"},POWERTOOLS_TRACER_CAPTURE_HTTPS_REQUESTS=${var.tracing_config.capture_http_requests},POWERTOOLS_TRACER_CAPTURE_ERROR=${var.tracing_config.capture_error},AWS_XRAY_SDK_ENABLED=true"
  }

  provisioner "local-exec" {
    command = "aws lambda update-function-configuration --function-name ${aws_lambda_function.ami_housekeeper.function_name} --environment-variables LOG_LEVEL=${var.log_level},POWERTOOLS_LOGGER_LOG_EVENT=${var.log_level == "debug"? "true" : "false"},AMI_CLEANUP_OPTIONS=${jsonencode(var.cleanup_config)},POWERTOOLS_SERVICE_NAME=ami-housekeeper,POWERTOOLS_TRACE_ENABLED=${var.tracing_config.mode!= null? "true" : "false"},POWERTOOLS_TRACER_CAPTURE_HTTPS_REQUESTS=${var.tracing_config.capture_http_requests},POWERTOOLS_TRACER_CAPTURE_ERROR=${var.tracing_config.capture_error},AWS_XRAY_SDK_ENABLED=true"
  }

  provisioner "local-exec" {
    command = "aws lambda update-function-configuration --function-name ${aws_lambda_function.ami_housekeeper.function_name} --environment-variables LOG_LEVEL=${var.log_level},POWERTOOLS_LOGGER_LOG_EVENT=${var.log_level == "debug"? "true" : "false"},AMI_CLEANUP_OPTIONS=${jsonencode(var.cleanup_config)},POWERTOOLS_SERVICE_NAME=ami-housekeeper,POWERTOOLS_TRACE_ENABLED=${var.tracing_config.mode!= null? "true" : "false"},POWERTOOLS_TRACER_CAPTURE_HTTPS_REQUESTS=${var.tracing_config.capture_http_requests},POWERTOOLS_TRACER_CAPTURE_ERROR=${var.tracing_config.capture_error},AWS_XRAY_SDK_ENABLED=true"
  }

  provisioner "local-exec" {
    command = "aws lambda update-function-configuration --function-name ${aws_lambda_function.ami_housekeeper.function_name} --environment-variables LOG_LEVEL=${var.log_level},POWERTOOLS_LOGGER_LOG_EVENT=${var.log_level == "debug"? "true" : "false"},AMI_CLEANUP_OPTIONS=${jsonencode(var.cleanup_config)},POWERTOOLS_SERVICE_NAME=ami-housekeeper,POWERTOOLS_TRACE_ENABLED=${var.tracing_config.mode!= null? "true" : "false"},POWERTOOLS_TRACER_CAPTURE_HTTPS_REQUESTS=${var.tracing_config.capture_http_requests},POWERTOOLS_TRACER_CAPTURE_ERROR=${var.tracing_config.capture_error},AWS_XRAY_SDK_ENABLED=true"
  }

  provisioner "local-exec" {
    command = "aws lambda update-function-configuration --function-name ${aws_lambda_function.ami_housekeeper.function_name} --environment-variables LOG_LEVEL=${var.log_level},POWERTOOLS_LOGGER_LOG_EVENT=${var.log_level == "debug"? "true" : "false"},AMI_CLEANUP_OPTIONS=${jsonencode(var.cleanup_config)},POWERTOOLS_SERVICE_NAME=ami-housekeeper,POWERTOOLS_TRACE_ENABLED=${var.tracing_config.mode!= null? "true" : "false"},POWERTOOLS_TRACER_CAPTURE_HTTPS_REQUESTS=${var.tracing_config.capture_http_requests},POWERTOOLS_TRACER_CAPTURE_ERROR=${var.tracing_config.capture_error},AWS_XRAY_SDK_ENABLED=true"
  }

  provisioner "local-exec" {
    command = "aws lambda update-function-configuration --function-name ${aws_lambda_function.ami_housekeeper.function_name} --environment-variables LOG_LEVEL=${var.log_level},POWERTOOLS_LOGGER_LOG_EVENT=${var.log_level == "debug"? "true" : "false"},AMI_CLEANUP_OPTIONS=${jsonencode(var.cleanup_config)},POWERTOOLS_SERVICE_NAME=ami-housekeeper,POWERTOOLS_TRACE_ENABLED=${var.tracing_config.mode!= null? "true" : "false"},POWERTOOLS_TRACER_CAPTURE_HTTPS_REQUESTS=${var.tracing_config.capture_http_requests},POWERTOOLS_TRACER_CAPTURE_ERROR=${var.tracing_config.capture_error},AWS_XRAY_SDK_ENABLED=true"
  }

  provisioner "local-exec" {
    command = "aws lambda update-function-configuration --function-name ${aws_lambda_function.ami_housekeeper.function_name} --environment-variables LOG_LEVEL=${var.log_level},POWERTOOLS_LOGGER_LOG_EVENT=${var.log_level == "debug"? "true" : "false"},AMI_CLEANUP_OPTIONS=${jsonencode(var.cleanup_config)},POWERTOOLS_SERVICE_NAME=ami-housekeeper,POWERTOOLS_TRACE_ENABLED=${var.tracing_config.mode!= null? "true" : "false"},POWERTOOLS_TRACER_CAPTURE_HTTPS_REQUESTS=${var.tracing_config.capture_http_requests},POWERTOOLS_TRACER_CAPTURE_ERROR=${var.tracing_config.capture_error},AWS_XRAY_SDK_ENABLED=true"
  }

  provisioner "local-exec" {
    command = "aws lambda update-function-configuration --function-name ${aws_lambda_function.ami_housekeeper.function_name} --environment-variables LOG_LEVEL=${var.log_level},POWERTOOLS_LOGGER_LOG_EVENT=${var.log_level == "debug"? "true" : "false"},AMI_CLEANUP_OPTIONS=${jsonencode(var.cleanup_config)},POWERTOOLS_SERVICE_NAME=ami-housekeeper,POWERTOOLS_TRACE_ENABLED=${var.tracing_config.mode!= null? "true" : "false"},POWERTOOLS_TRACER_CAPTURE_HTTPS_REQUESTS=${var.tracing_config.capture_http_requests},POWERTOOLS_TRACER_CAPTURE_ERROR=${var.tracing_config.capture_error},AWS_XRAY_SDK_ENABLED=true"
  }

  provisioner "local-exec" {
    command = "aws lambda update-function-configuration --function-name ${aws_lambda_function.ami_housekeeper.function_name} --environment-variables LOG_LEVEL=${var.log_level},POWERTOOLS_LOGGER_LOG_EVENT=${var.log_level == "debug"? "true" : "false"},AMI_CLEANUP_OPTIONS=${jsonencode(var.cleanup_config)},POWERTOOLS_SERVICE_NAME=ami-housekeeper,POWERTOOLS_TRACE_ENABLED=${var.tracing_config.mode!= null? "true" : "false"},POWERTOOLS_TRACER_CAPTURE_HTTPS_REQUESTS=${var.tracing_config.capture_http_requests},POWERTOOLS_TRACER_CAPTURE_ERROR=${var.tracing_config.capture_error},AWS_XRAY_SDK_ENABLED=true"
  }

  provisioner "local-exec" {
    command = "aws lambda update-function-configuration --function-name ${aws_lambda_function.ami_housekeeper.function_name} --environment-variables LOG_LEVEL=${var.log_level},POWERTOOLS_LOGGER_LOG_EVENT=${var.log_level == "debug"? "true" : "false"},AMI_CLEANUP_OPTIONS=${jsonencode(var.cleanup_config)},POWERTOOLS_SERVICE_NAME=ami-housekeeper,POWERTOOLS_TRACE_ENABLED=${var.tracing_config.mode!= null? "true" : "false"},POWERTOOLS_TRACER_CAPTURE_HTTPS_REQUESTS=${var.tracing_config.capture_http_requests},POWERTOOLS_TRACER_CAPTURE_ERROR=${var.tracing_config.capture_error},AWS_XRAY_SDK_ENABLED=true"
  }

  provisioner "local-exec" {
    command = "aws lambda update-function-configuration --function-name ${aws_lambda_function.ami_housekeeper.function_name} --environment-variables LOG_LEVEL=${var.log_level},POWERTOOLS_LOGGER_LOG_EVENT=${var.log_level == "debug"? "true" : "false"},AMI_CLEANUP_OPTIONS=${jsonencode(var.cleanup_config)},POWERTOOLS_SERVICE_NAME=ami-housekeeper,POWERTOOLS_TRACE_ENABLED=${var.tracing_config.mode!= null? "true" : "false"},POWERTOOLS_TRACER_CAPTURE_HTTPS_REQUESTS=${var.tracing_config.capture_http_requests},POWERTOOLS_TRACER_CAPTURE_ERROR=${var.tracing_config.capture_error},AWS_XRAY_SDK_ENABLED=true"
  }

  provisioner "local-exec" {
    command = "aws lambda update-function-configuration --function-name ${aws_lambda_function.ami_housekeeper.function_name} --environment-variables LOG_LEVEL=${var.log_level},POWERTOOLS_LOGGER_LOG_EVENT=${var.log_level == "debug"? "true" : "false"},AMI_CLEANUP_OPTIONS=${jsonencode(var.cleanup_config)},POWERTOOLS_SERVICE_NAME=ami-housekeeper,POWERTOOLS_TRACE_ENABLED=${var.tracing_config.mode!= null? "true" : "false"},POWERTOOLS_TRACER_CAPTURE_HTTPS_REQUESTS=${var.tracing_config.capture_http_requests},POWERTOOLS_TRACER_CAPTURE_ERROR=${var.tracing_config.capture_error},AWS_XRAY_SDK_ENABLED=true"
  }

  provisioner "local-exec" {
    command = "aws lambda update-function-configuration --function-name ${aws_lambda_function.ami_housekeeper.function_name} --environment-variables LOG_LEVEL=${var.log_level},POWERTOOLS_LOGGER_LOG_EVENT=${var.log_level == "debug"? "true" : "false"},AMI_CLEANUP_OPTIONS=${jsonencode(var.cleanup_config)},POWERTOOLS_SERVICE_NAME=ami-housekeeper,POWERTOOLS_TRACE_ENABLED=${var.tracing_config.mode!= null? "true" : "false"},POWERTOOLS_TRACER_CAPTURE_HTTPS_REQUESTS=${var.tracing_config.capture_http_requests},POWERTOOLS_TRACER_CAPTURE_ERROR=${var.tracing_config.capture_error},AWS_XRAY_SDK_ENABLED=true"
  }

  provisioner "local-exec" {
    command = "aws lambda update-function-configuration --function-name ${aws_lambda_function.ami_housekeeper.function_name} --environment-variables LOG_LEVEL=${var.log_level},POWERTOOLS_LOGGER_LOG_EVENT=${var.log_level == "debug"? "true" : "false"},AMI_CLEANUP_OPTIONS=${jsonencode(var.cleanup_config)},POWERTOOLS_SERVICE_NAME=ami-housekeeper,POWERTOOLS_TRACE_ENABLED=${var.tracing_config.mode!= null? "true" : "false"},POWERTOOLS_TRACER_CAPTURE_HTTPS_REQUESTS=${var.tracing_config.capture_http_requests},POWERTOOLS_TRACER_CAPTURE_ERROR=${var.tracing_config.capture_error},AWS_XRAY_SDK_ENABLED=true"
  }

  provisioner "local-exec" {
    command = "aws lambda update-function-configuration --function-name ${aws_lambda_function.ami_housekeeper.function_name} --environment-variables LOG_LEVEL=${var.log_level},POWERTOOLS_LOGGER_LOG_EVENT=${var.log_level == "debug"? "true" : "false"},AMI_CLEANUP_OPTIONS=${jsonencode(var.cleanup_config)},POWERTOOLS_SERVICE_NAME=ami-housekeeper,POWERTOOLS_TRACE_ENABLED=${var.tracing_config.mode!= null? "true" : "false"},POWERTOOLS_TRACER_CAPTURE_HTTPS_REQUESTS=${var.tracing_config.capture_http_requests},POWERTOOLS_TRACER_CAPTURE_ERROR=${var.tracing_config.capture_error},AWS_XRAY_SDK_ENABLED=true"
  }

  provisioner "local-exec" {
    command = "aws lambda update-function-configuration --function-name ${aws_lambda_function.ami_housekeeper.function_name} --environment-variables LOG_LEVEL=${var.log_level},POWERTOOLS_LOGGER_LOG_EVENT=${var.log_level == "debug"? "true" : "false"},AMI_CLEANUP_OPTIONS=${jsonencode(var.cleanup_config)},POWERTOOLS_SERVICE_NAME=ami-housekeeper,POWERTOOLS_TRACE_ENABLED=${var.tracing_config.mode!= null? "true" : "false"},POWERTOOLS_TRACER_CAPTURE_HTTPS_REQUESTS=${var.tracing_config.capture_http_requests},POWERTOOLS_TRACER_CAPTURE_ERROR=${var.tracing_config.capture_error},AWS_XRAY_SDK_ENABLED=true"
  }

  provisioner "local-exec" {
    command = "aws lambda update-function-configuration --function-name ${aws_lambda_function.ami_housekeeper.function_name} --environment-variables LOG_LEVEL=${var.log_level},POWERTOOLS_LOGGER_LOG_EVENT=${var.log_level == "debug"? "true" : "false"},AMI_CLEANUP_OPTIONS=${jsonencode(var.cleanup_config)},POWERTOOLS_SERVICE_NAME=ami-housekeeper,POWERTOOLS_TRACE_ENABLED=${var.tracing_config.mode!= null? "true" : "false"},POWERTOOLS_TRACER_CAPTURE_HTTPS_REQUESTS=${var.tracing_config.capture_http_requests},POWERTOOLS_TRACER_CAPTURE_ERROR=${var.tracing_config.capture_error},AWS_XRAY_SDK_ENABLED=true"
  }

  provisioner "local-exec" {
    command = "aws lambda update-function-configuration --function-name ${aws_lambda_function.ami_housekeeper.function_name} --environment-variables LOG_LEVEL=${var.log_level},POWERTOOLS_LOGGER_LOG_EVENT=${var.log_level == "debug"? "true" : "false"},AMI_CLEANUP_OPTIONS=${jsonencode(var.cleanup_config)},POWERTOOLS_SERVICE_NAME=ami-housekeeper,POWERTOOLS_TRACE_ENABLED=${var.tracing_config.mode!= null? "true" : "false"},POWERTOOLS_TRACER_CAPTURE_HTTPS_REQUESTS=${var.tracing_config.capture_http_requests},POWERTOOLS_TRACER_CAPTURE_ERROR=${var.tracing_config.capture_error},AWS_XRAY_SDK_ENABLED=true"
  }

  provisioner "local-exec" {
    command = "aws lambda update-function-configuration --function-name ${aws_lambda_function.ami_housekeeper.function_name} --environment-variables LOG_LEVEL=${var.log_level},POWERTOOLS_LOGGER_LOG_EVENT=${var.log_level == "debug"? "true" : "false"},AMI_CLEANUP_OPTIONS=${jsonencode(var.cleanup_config)},POWERTOOLS_SERVICE_NAME=ami-housekeeper,POWERTOOLS_TRACE_ENABLED=${var.tracing_config.mode!= null? "true" : "false"},POWERTOOLS_TRACER_CAPTURE_HTTPS_REQUESTS=${var.tracing_config.capture_http_requests},POWERTOOLS_TRACER_CAPTURE_ERROR=${var.tracing_config.capture_error},AWS_XRAY_SDK_ENABLED=true"
  }

  provisioner "local-exec" {
    command = "aws lambda update-function-configuration --function-name ${aws_lambda_function.ami_housekeeper.function_name} --environment-variables LOG_LEVEL=${var.log_level},POWERTOOLS_LOGGER_LOG_EVENT=${var.log_level == "debug"? "true" : "false"},AMI_CLEANUP_OPTIONS=${jsonencode(var.cleanup_config)},POWERTOOLS_SERVICE_NAME=ami-housekeeper,POWERTOOLS_TRACE_ENABLED=${var.tracing_config.mode!= null? "true" : "false"},POWERTOOLS_TRACER_CAPTURE_HTTPS_REQUESTS=${var.tracing_config.capture_http_requests},POWERTOOLS_TRACER_CAPTURE_ERROR=${var.tracing_config.capture_error},AWS_XRAY_SDK_ENABLED=true"
  }

  provisioner "local-exec" {
    command = "aws lambda update-function-configuration --function-name ${aws_lambda_function.ami_housekeeper.function_name} --environment-variables LOG_LEVEL=${var.log_level},POWERTOOLS_LOGGER_LOG_EVENT=${var.log_level == "debug"? "true" : "false"},AMI_CLEANUP_OPTIONS=${jsonencode(var.cleanup_config)},POWERTOOLS_SERVICE_NAME=ami-housekeeper,POWERTOOLS_TRACE_ENABLED=${var.tracing_config.mode!= null? "true" : "false"},POWERTOOLS_TRACER_CAPTURE_HTTPS_REQUESTS=${var.tracing_config.capture_http_requests},POWERTOOLS_TRACER_CAPTURE_ERROR=${var.tracing_config.capture_error},AWS_XRAY_SDK_ENABLED=true"
  }

  provisioner "local-exec" {
    command = "aws lambda update-function-configuration --function-name ${aws_lambda_function.ami_housekeeper.function_name} --environment-variables LOG_LEVEL=${var.log_level},POWERTOOLS_LOGGER_LOG_EVENT=${var.log_level == "debug"? "true" : "false"},AMI_CLEANUP_OPTIONS=${jsonencode(var.cleanup_config)},POWERTOOLS_SERVICE_NAME=ami-housekeeper,POWERTOOLS_TRACE_ENABLED=${var.tracing_config.mode!= null? "true" : "false"},POWERTOOLS_TRACER_CAPTURE_HTTPS_REQUESTS=${var.tracing_config.capture_http_requests},POWERTOOLS_TRACER_CAPTURE_ERROR=${var.tracing_config.capture_error},AWS_XRAY_SDK_ENABLED=true"
  }

  provisioner "local-exec" {
    command = "aws lambda update-function-configuration --function-name ${aws_lambda_function.ami_housekeeper.function_name} --environment-variables LOG_LEVEL=${var.log_level},POWERTOOLS_LOGGER_LOG_EVENT=${var.log_level == "debug"? "true" : "false"},AMI_CLEANUP_OPTIONS=${jsonencode(var.cleanup_config)},POWERTOOLS_SERVICE_NAME=ami-housekeeper,POWERTOOLS_TRACE_ENABLED=${var.tracing_config.mode!= null ? "true" : "false"},POWERTOOLS_TRACER_CAPTURE_HTTPS_REQUESTS=${var.tracing_config.capture_http_requests},POWERTOOLS_TRACER_CAPTURE_ERROR=${var.tracing_config.capture_error},AWS_XRAY_SDK_ENABLED=true"
  }

  provisioner "local-exec" {
    command = "aws lambda update-function-configuration --function-name ${aws_lambda_function.ami_housekeeper.function_name} --environment-variables LOG_LEVEL=${var.log_level},POWERTOOLS_LOGGER_LOG_EVENT=${var.log_level == "debug"? "true" : "false"},AMI_CLEANUP_OPTIONS=${jsonencode(var.cleanup_config)},POWERTOOLS_SERVICE_NAME=ami-housekeeper,POWERTOOLS_TRACE_ENABLED=${var.tracing_config.mode!= null? "true" : "false"},POWERTOOLS_TRACER_CAPTURE_HTTPS_REQUESTS=${var.tracing_config.capture_http_requests},POWERTOOLS_TRACER_CAPTURE_ERROR=${var.tracing_config.capture_error},AWS_XRAY_SDK_ENABLED=true"
  }

  provisioner "local-exec" {
    command = "aws lambda update-function-configuration --function-name ${aws_lambda_function.ami_housekeeper.function_name} --environment-variables LOG_LEVEL=${var.log_level},POWERTOOLS_LOGGER_LOG_EVENT=${var.log_level == "debug"? "true" : "false"},AMI_CLEANUP_OPTIONS=${jsonencode(var.cleanup_config)},POWERTOOLS_SERVICE_NAME=ami-housekeeper,POWERTOOLS_TRACE_ENABLED=${var.tracing_config.mode!= null? "true" : "false"},POWERTOOLS_TRACER_CAPTURE_HTTPS_REQUESTS=${var.tracing_config.capture_http_requests},POWERTOOLS_TRACER_CAPTURE_ERROR=${var.tracing_config.capture_error},AWS_XRAY_SDK_ENABLED=true"
  }

  provisioner "local-exec" {
    command = "aws lambda update-function-configuration --function-name ${aws_lambda_function.ami_housekeeper.function_name} --environment-variables LOG_LEVEL=${var.log_level},POWERTOOLS_LOGGER_LOG_EVENT=${var.log_level == "debug"? "true" : "false"},AMI_CLEANUP_OPTIONS=${jsonencode(var.cleanup_config)},POWERTOOLS_SERVICE_NAME=ami-housekeeper,POWERTOOLS_TRACE_ENABLED=${var.tracing_config.mode!= null? "true" : "false"},POWERTOOLS_TRACER_CAPTURE_HTTPS_REQUESTS=${var.tracing_config.capture_http_requests},POWERTOOLS_TRACER_CAPTURE_ERROR=${var.tracing_config.capture_error},AWS_XRAY_SDK_ENABLED=true"
  }

  provisioner "local-exec" {
    command = "aws lambda update-function-configuration --function-name ${aws_lambda_function.ami_housekeeper.function_name} --environment-variables LOG_LEVEL=${var.log_level},POWERTOOLS_LOGGER_LOG_EVENT=${var.log_level == "debug"? "true" : "false"},AMI_CLEANUP_OPTIONS=${jsonencode(var.cleanup_config)},POWERTOOLS_SERVICE_NAME=ami-housekeeper,POWERTOOLS_TRACE_ENABLED=${var.tracing_config.mode!= null ? "true" : "false"},POWERTOOLS_TRACER_CAPTURE_HTTPS_REQUESTS=${var.tracing_config.capture_http_requests},POWERTOOLS_TRACER_CAPTURE_ERROR=${var.tracing_config.capture_error},AWS_XRAY_SDK_ENABLED=true"
  }

  provisioner "local-exec" {
    command = "aws lambda update-function-configuration --function-name ${aws_lambda_function.ami_housekeeper.function_name} --environment-variables LOG_LEVEL=${var.log_level},POWERTOOLS_LOGGER_LOG_EVENT=${var.log_level == "debug"? "true" : "false"},AMI_CLEANUP_OPTIONS=${jsonencode(var.cleanup_config)},POWERTOOLS_SERVICE_NAME=ami-housekeeper,POWERTOOLS_TRACE_ENABLED=${var.tracing_config.mode!= null? "true" : "false"},POWERTOOLS_TRACER_CAPTURE_HTTPS_REQUESTS=${var.tracing_config.capture_http_requests},POWERTOOLS_TRACER_CAPTURE_ERROR=${var.tracing_config.capture_error},AWS_XRAY_SDK_ENABLED=true"
  }

  provisioner "local-exec" {
    command = "aws lambda update-function-configuration --function-name ${aws_lambda_function.ami_housekeeper.function_name} --environment-variables LOG_LEVEL=${var.log_level},POWERTOOLS_LOGGER_LOG_EVENT=${var.log_level == "debug"? "true" : "false"},AMI_CLEANUP_OPTIONS=${jsonencode(var.cleanup_config)},POWERTOOLS_SERVICE_NAME=ami-housekeeper,POWERTOOLS_TRACE_ENABLED=${var.tracing_config.mode!= null? "true" : "false"},POWERTOOLS_TRACER_CAPTURE_HTTPS_REQUESTS=${var.tracing_config.capture_http_requests},POWERTOOLS_TRACER_CAPTURE_ERROR=${var.tracing_config.capture_error},AWS_XRAY_SDK_ENABLED=true"
  }

  provisioner "local-exec" {
    command = "aws lambda update-function-configuration --function-name ${aws_lambda_function.ami_housekeeper.function_name} --environment-variables LOG_LEVEL=${var.log_level},POWERTOOLS_LOGGER_LOG_EVENT=${var.log_level == "debug"? "true" : "false"},AMI_CLEANUP_OPTIONS=${jsonencode(var.cleanup_config)},POWERTOOLS_SERVICE_NAME=ami-housekeeper,POWERTOOLS_TRACE_ENABLED=${var.tracing_config.mode!= null ? "true" : "false"},POWERTOOLS_TRACER_CAPTURE_HTTPS_REQUESTS=${var.tracing_config.capture_http_requests},POWERTOOLS_TRACER_CAPTURE_ERROR=${var.tracing_config.capture_error},AWS_XRAY_SDK_ENABLED=true"
  }

  provisioner "local-exec" {
    command = "aws lambda update-function-configuration --function-name ${aws_lambda_function.ami_housekeeper.function_name} --environment-variables LOG_LEVEL=${var.log_level},POWERTOOLS_LOGGER_LOG_EVENT=${var.log_level == "debug"? "true" : "false"},AMI_CLEANUP_OPTIONS=${jsonencode(var.cleanup_config)},POWERTOOLS_SERVICE_NAME=ami-housekeeper,POWERTOOLS_TRACE_ENABLED=${var.tracing_config.mode!= null? "true" : "false"},POWERTOOLS_TRACER_CAPTURE_HTTPS_REQUESTS=${var.tracing_config.capture_http_requests},POWERTOOLS_TRACER_CAPTURE_ERROR=${var.tracing_config.capture_error},AWS_XRAY_SDK_ENABLED=true"
  }

  provisioner "local-exec" {
    command = "aws lambda update-function-configuration --function-name ${aws_lambda_function.ami_housekeeper.function_name} --environment-variables LOG_LEVEL=${var.log_level},POWERTOOLS_LOGGER_LOG_EVENT=${var.log_level == "debug"? "true" : "false"},AMI_CLEANUP_OPTIONS=${jsonencode(var.cleanup_config)},POWERTOOLS_SERVICE_NAME=ami-housekeeper,POWERTOOLS_TRACE_ENABLED=${var.tracing_config.mode!= null ? "true" : "false"},POWERTOOLS_TRACER_CAPTURE_HTTPS_REQUESTS=${var.tracing_config.capture_http_requests},POWERTOOLS_TRACER_CAPTURE_ERROR=${var.tracing_config.capture_error},AWS_XRAY_SDK_ENABLED=true"
  }

  provisioner "local-exec" {
    command = "aws lambda update-function-configuration --function-name ${aws_lambda_function.ami_housekeeper.function_name} --environment-variables LOG_LEVEL=${var.log_level},POWERTOOLS_LOGGER_LOG_EVENT=${var.log_level == "debug"? "true" : "false"},AMI_CLEANUP_OPTIONS=${jsonencode(var.cleanup_config)},POWERTOOLS_SERVICE_NAME=ami-housekeeper,POWERTOOLS_TRACE_ENABLED=${var.tracing_config.mode!= null ? "true" : "false"},POWERTOOLS_TRACER_CAPTURE_HTTPS_REQUESTS=${