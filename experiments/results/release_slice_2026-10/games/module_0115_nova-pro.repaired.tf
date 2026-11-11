data "aws_iam_policy_document" "lambda_xray" {
  count = var.lambda.tracing_config.mode!= null ? 1 : 0
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
  role_path = var.lambda.role_path == null ? "/${var.lambda.prefix}/" : var.lambda.role_path

  lambda_environment_variables = {
    ENVIRONMENT                              = var.lambda.prefix
    LOG_LEVEL                                = var.lambda.log_level
    PREFIX                                   = var.lambda.prefix
    POWERTOOLS_LOGGER_LOG_EVENT              = var.lambda.log_level == "debug"? "true" : "false"
    POWERTOOLS_SERVICE_NAME                  = var.lambda.name
    POWERTOOLS_TRACE_ENABLED                 = var.lambda.tracing_config.mode!= null ? true : false
    POWERTOOLS_TRACER_CAPTURE_HTTPS_REQUESTS = var.lambda.tracing_config.capture_http_requests
    POWERTOOLS_TRACER_CAPTURE_ERROR          = var.lambda.tracing_config.capture_error
    POWERTOOLS_METRICS_NAMESPACE             = var.lambda.metrics_namespace
  }

  environment_variable = merge(local.lambda_environment_variables, var.lambda.environment_variables)
}

resource "aws_lambda_function" "main" {
  s3_bucket         = var.lambda.s3_bucket!= null ? var.lambda.s3_bucket : null
  s3_key            = var.lambda.s3_key!= null ? var.lambda.s3_key : null
  s3_object_version = var.lambda.s3_object_version!= null ? var.lambda.s3_object_version : null
  filename          = var.lambda.s3_bucket == null? var.lambda.zip : null
  source_code_hash  = var.lambda.s3_bucket == null ? filebase64sha256(var.lambda.zip) : null
  function_name     = "${var.lambda.prefix}-${var.lambda.name}"
  role              = aws_iam_role.main.arn
  handler           = var.lambda.handler
  runtime           = var.lambda.runtime
  timeout           = var.lambda.timeout
  memory_size       = var.lambda.memory_size
  architectures     = [var.lambda.architecture]

  environment {
    variables = local.environment_variable
  }

  dynamic "vpc_config" {
    for_each = var.lambda.subnet_ids!= null && var.lambda.security_group_ids!= null? [true] : []
    content {
      security_group_ids = var.lambda.security_group_ids
      subnet_ids         = var.lambda.subnet_ids
    }
  }

  tags = merge(var.lambda.tags, var.lambda.lambda_tags)

  dynamic "tracing_config" {
    for_each = var.lambda.tracing_config.mode!= null? [true] : []
    content {
      mode = var.lambda.tracing_config.mode
    }
  }

  dynamic "dead_letter_config" {
    for_each = var.lambda.dead_letter_config!= null ? [true] : []
    content {
      target_arn = var.lambda.dead_letter_config.target_arn
    }
  }

  dynamic "kms_key_arn" {
    for_each = var.lambda.kms_key_arn!= null ? [true] : []
    content {
      kms_key_arn = var.lambda.kms_key_arn
    }
  }

  reserved_concurrent_executions = var.lambda.reserved_concurrent_executions!= null ? var.lambda.reserved_concurrent_executions : null

  dynamic "code_signing_config_arn" {
    for_each = var.lambda.code_signing_config_arn!= null? [true] : []
    content {
      code_signing_config_arn = var.lambda.code_signing_config_arn
    }
  }
}

resource "aws_cloudwatch_log_group" "main" {
  name              = "/aws/lambda/${aws_lambda_function.main.function_name}"
  retention_in_days = var.lambda.logging_retention_in_days
  kms_key_id        = var.lambda.logging_kms_key_id
  tags              = var.lambda.tags
}

resource "aws_iam_role" "main" {
  name                 = "${var.lambda.prefix}-${var.lambda.name}"
  assume_role_policy   = data.aws_iam_policy_document.lambda_assume_role_policy.json
  path                 = local.role_path
  permissions_boundary = var.lambda.role_permissions_boundary

  tags = var.lambda.tags
}

data "aws_iam_policy_document" "lambda_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }

    dynamic "principals" {
      for_each = var.lambda.principals

      content {
        type        = principals.value.type
        identifiers = principals.value.identifiers
      }
    }
  }
}

resource "aws_iam_role_policy" "lambda_logging" {
  name = "logging-policy"
  role = aws_iam_role.main.id

  policy = templatefile("${path.module}/policies/lambda-cloudwatch.json", {
    log_group_arn = aws_cloudwatch_log_group.main.arn
  })
}

resource "aws_iam_role_policy_attachment" "vpc_execution_role" {
  count      = length(var.lambda.subnet_ids) > 0 ? 1 : 0
  role       = aws_iam_role.main.name
  policy_arn = "arn:${var.lambda.aws_partition}:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy" "xray" {
  count  = var.lambda.tracing_config.mode!= null? 1 : 0
  name   = "xray-policy"
  policy = data.aws_iam_policy_document.lambda_xray[0].json
  role   = aws_iam_role.main.name
}

output "lambda" {
  value = {
    function  = aws_lambda_function.main
    log_group = aws_cloudwatch_log_group.main
    role      = aws_iam_role.main
  }
}

variable "lambda" {
  description = <<-EOF
    Configuration for the lambda function.

    `aws_partition`: Partition for the base arn if not 'aws'
    `architecture`: AWS Lambda architecture. Lambda functions using Graviton processors ('arm64') tend to have better price/performance than 'x86_64' functions.
    `environment_variables`: Environment variables for the lambda.
    `handler`: The entrypoint for the lambda.
    `principals`: Add extra principals to the role created for execution of the lambda, e.g. for local testing.
    `lambda_tags`: Map of tags that will be added to created resources. By default resources will be tagged with name and environment.
    `log_level`: Logging level for lambda logging. Valid values are  'silly', 'trace', 'debug', 'info', 'warn', 'error', 'fatal'.
    `logging_kms_key_id`: Specifies the kms key id to encrypt the logs with
    `logging_retention_in_days`: Specifies the number of days you want to retain log events for the lambda log group. Possible values are: 0, 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, and 3653.
    `memory_size`: Memory size linit in MB of the lambda.
    `metrics_namespace`: Namespace for the metrics emitted by the lambda.
    `name`: The name of the lambda function.
    `prefix`: The prefix used for naming resources.
    `role_path`: The path that will be added to the role, if not set the environment name will be used.
    `role_permissions_boundary`: Permissions boundary that will be added to the created role for the lambda.
    `runtime`: AWS Lambda runtime.
    `s3_bucket`: S3 bucket from which to specify lambda functions. This is an alternative to providing local files directly.
    `s3_key`: S3 key for syncer lambda function. Required if using S3 bucket to specify lambdas.
    `s3_object_version`: S3 object version for syncer lambda function. Useful if S3 versioning is enabled on source bucket.
    `security_group_ids`: List of security group IDs associated with the Lambda function.
    `subnet_ids`: List of subnets in which the action runners will be launched, the subnets needs to be subnets in the `vpc_id`.
    `tags`: Map of tags that will be added to created resources. By default resources will be tagged with name and environment.
    `timeout`: Time out of the lambda in seconds.
    `tracing_config`: Configuration for lambda tracing.
    `zip`: File location of the lambda zip file.
  EOF
  type = object({
    aws_partition             = optional(string, "aws")
    architecture              = optional(string, "arm64")
    environment_variables     = optional(map(string), {})
    handler                   = string
    lambda_tags               = optional(map(string), {})
    log_level                 = optional(string, "info")
    logging_kms_key_id        = optional(string, null)
    logging_retention_in_days = optional(number, 180)
    memory_size               = optional(number, 256)
    metrics_namespace         = optional(string, "GitHub Runners")
    name                      = string
    prefix                    = optional(string, null)
    principals = optional(list(object({
      type        = string
      identifiers = list(string)
    })), [])
    role_path                 = optional(string, null)
    role_permissions_boundary = optional(string, null)
    runtime                   = optional(string, "nodejs22.x")
    s3_bucket                 = optional(string, null)
    s3_key                    = optional(string, null)
    s3_object_version         = optional(string, null)
    security_group_ids        = optional(list(string), [])
    subnet_ids                = optional(list(string), [])
    tags                      = optional(map(string), {})
    timeout                   = optional(number, 60)
    tracing_config = optional(object({
      mode                  = optional(string, null)
      capture_http_requests = optional(bool, false)
      capture_error         = optional(bool, false)
    }), {})
    zip = optional(string, null)
    dead_letter_config = optional(object({
      target_arn = string
    }), null)
    kms_key_arn = optional(string, null)
    reserved_concurrent_executions = optional(number, null)
    code_signing_config_arn = optional(string, null)
  })

  validation {
    condition     = var.lambda.zip!= null || (var.lambda.s3_bucket!= null && var.lambda.s3_key!= null)
    error_message = "Either `lambda_zip` or `lambda_s3_bucket` and `lambda_s3_key` must be provided."
  }
  validation {
    condition     = var.lambda.architecture == "arm64" || var.lambda.architecture == "x86_64"
    error_message = "`lambda_architecture` value is not valid, valid values are: `arm64` and `x86_64`."
  }
  validation {
    condition = anytrue([
      var.lambda.log_level == "debug",
      var.lambda.log_level == "info",
      var.lambda.log_level == "warn",
      var.lambda.log_level == "error",
    ])
    error_message = "`log_level` value not valid. Valid values are 'debug', 'info', 'warn', 'error'."

  }
  validation {
    condition     = length(var.lambda.name) + length(var.lambda.prefix) <= 63
    error_message = "The length of `name` + `prefix` must be less than or equal to 63."
  }
}

terraform {
  required_version = ">= 1.3.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.27"
    }
  }
}