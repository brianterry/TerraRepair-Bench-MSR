data "aws_iam_policy_document" "lambda_xray" {
  count = var.tracing_config.mode != null ? 1 : 0
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
  lambda_zip = var.lambda_zip == null ? "${path.module}/../../lambdas/functions/ami-housekeeper/ami-housekeeper.zip" : var.lambda_zip
  role_path  = var.role_path == null ? "/${var.prefix}/" : var.role_path
}

resource "aws_lambda_function" "ami_housekeeper" {
  s3_bucket         = var.lambda_s3_bucket != null ? var.lambda_s3_bucket : null
  s3_key            = var.lambda_s3_key != null ? var.lambda_s3_key : null
  s3_object_version = var.lambda_s3_object_version != null ? var.lambda_s3_object_version : null
  filename          = var.lambda_s3_bucket == null ? local.lambda_zip : null
  source_code_hash  = var.lambda_s3_bucket == null ? filebase64sha256(local.lambda_zip) : null
  function_name     = "${var.prefix}-ami-housekeeper"
  role              = aws_iam_role.ami_housekeeper.arn
  handler           = "index.handler"
  runtime           = var.lambda_runtime
  timeout           = var.lambda_timeout
  memory_size       = var.lambda_memory_size
  architectures     = [var.lambda_architecture]
  reserved_concurrent_executions = var.lambda_reserved_concurrent_executions

  environment {
    variables = {
      LOG_LEVEL                                = var.log_level
      POWERTOOLS_LOGGER_LOG_EVENT              = var.log_level == "debug" ? "true" : "false"
      AMI_CLEANUP_OPTIONS                      = jsonencode(var.cleanup_config)
      POWERTOOLS_SERVICE_NAME                  = "ami-housekeeper"
      POWERTOOLS_TRACE_ENABLED                 = var.tracing_config.mode != null ? true : false
      POWERTOOLS_TRACER_CAPTURE_HTTPS_REQUESTS = var.tracing_config.capture_http_requests
      POWERTOOLS_TRACER_CAPTURE_ERROR          = var.tracing_config.capture_error
    }
  }

  dynamic "vpc_config" {
    for_each = var.lambda_subnet_ids != null && var.lambda_security_group_ids != null ? [true] : []
    content {
      security_group_ids = var.lambda_security_group_ids
      subnet_ids         = var.lambda_subnet_ids
    }
  }

  tags = merge(var.tags, var.lambda_tags)

  tracing_config {
    mode = var.tracing_config.mode != null ? var.tracing_config.mode : "Active"
  }

  dynamic "dead_letter_config" {
    for_each = var.lambda_dlq_target_arn != null ? [true] : []
    content {
      target_arn = var.lambda_dlq_target_arn
    }
  }

  code_signing_config_arn = var.lambda_code_signing_config_arn
}

resource "aws_cloudwatch_log_group" "ami_housekeeper" {
  name              = "/aws/lambda/${aws_lambda_function.ami_housekeeper.function_name}"
  retention_in_days = var.logging_retention_in_days >= 365 ? var.logging_retention_in_days : 365
  kms_key_id        = var.logging_kms_key_id
  tags              = var.tags
}

resource "aws_iam_role" "ami_housekeeper" {
  name                 = "${var.prefix}-ami-housekeeper-role"
  assume_role_policy   = data.aws_iam_policy_document.lambda_assume_role_policy.json
  path                 = local.role_path
  permissions_boundary = var.role_permissions_boundary

  tags = var.tags
}

data "aws_iam_policy_document" "lambda_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }

    dynamic "principals" {
      for_each = var.lambda_principals

      content {
        type        = principals.value.type
        identifiers = principals.value.identifiers
      }
    }
  }
}

resource "aws_iam_role_policy" "lambda_logging" {
  name = "logging-policy"
  role = aws_iam_role.ami_housekeeper.id

  policy = templatefile("${path.module}/policies/lambda-cloudwatch.json", {
    log_group_arn = aws_cloudwatch_log_group.ami_housekeeper.arn
  })
}

resource "aws_iam_role_policy" "ami_housekeeper" {
  name = "lambda-ami-policy"
  role = aws_iam_role.ami_housekeeper.id

  policy = templatefile("${path.module}/policies/lambda-ami-housekeeper.json", {})
}

resource "aws_cloudwatch_event_rule" "ami_housekeeper" {
  name                = "${var.prefix}-ami-housekeeper"
  schedule_expression = var.lambda_schedule_expression
  tags                = var.tags
  state               = var.state_event_rule_ami_housekeeper
}

resource "aws_cloudwatch_event_target" "ami_housekeeper" {
  rule = aws_cloudwatch_event_rule.ami_housekeeper.name
  arn  = aws_lambda_function.ami_housekeeper.arn
}

resource "aws_iam_role_policy_attachment" "ami_housekeeper_vpc_execution_role" {
  count      = length(var.lambda_subnet_ids) > 0 ? 1 : 0
  role       = aws_iam_role.ami_housekeeper.name
  policy_arn = "arn:${var.aws_partition}:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_lambda_permission" "ami_housekeeper" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ami_housekeeper.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.ami_housekeeper.arn
}

resource "aws_iam_role_policy" "ami_housekeeper_xray" {
  count  = var.tracing_config.mode != null ? 1 : 0
  name   = "xray-policy"
  policy = data.aws_iam_policy_document.lambda_xray[0].json
  role   = aws_iam_role.ami_housekeeper.name
}

output "lambda" {
  value = aws_lambda_function.ami_housekeeper
}

output "lambda_log_group" {
  value = aws_cloudwatch_log_group.ami_housekeeper
}

output "lambda_role" {
  value = aws_iam_role.ami_housekeeper
}

variable "tags" {
  description = "Map of tags that will be added to created resources. By default resources will be tagged with name and environment."
  type        = map(string)
  default     = {}
}

variable "prefix" {
  description = "The prefix used for naming resources"
  type        = string
  default     = "github-actions"
}

variable "lambda_zip" {
  description = "File location of the lambda zip file."
  type        = string
  default     = null
}

variable "lambda_timeout" {
  description = "Time out of the lambda in seconds."
  type        = number
  default     = 60
}

variable "lambda_memory_size" {
  description = "Memory size linit in MB of the lambda."
  type        = number
  default     = 256
}

variable "role_permissions_boundary" {
  description = "Permissions boundary that will be added to the created role for the lambda."
  type        = string
  default     = null
}

variable "role_path" {
  description = "The path that will be added to the role, if not set the environment name will be used."
  type        = string
  default     = null
}

variable "logging_retention_in_days" {
  description = "Specifies the number of days you want to retain log events for the lambda log group. Possible values are: 0, 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, and 3653."
  type        = number
  default     = 365
}

variable "logging_kms_key_id" {
  description = "Specifies the kms key id to encrypt the logs with"
  type        = string
  default     = null
}

variable "lambda_subnet_ids" {
  description = "List of subnets in which the action runners will be launched, the subnets needs to be subnets in the `vpc_id`."
  type        = list(string)
  default     = []
}

variable "lambda_security_group_ids" {
  description = "List of security group IDs associated with the Lambda function."
  type        = list(string)
  default     = []
}

variable "aws_partition" {
  description = "(optional) partition for the base arn if not 'aws'"
  type        = string
  default     = "aws"
}

variable "log_level" {
  description = "Logging level for lambda logging. Valid values are  'silly', 'trace', 'debug', 'info', 'warn', 'error', 'fatal'."
  type        = string
  default     = "info"
  validation {
    condition = anytrue([
      var.log_level == "debug",
      var.log_level == "info",
      var.log_level == "warn",
      var.log_level == "error",
    ])
    error_message = "`log_level` value not valid. Valid values are 'debug', 'info', 'warn', 'error'."
  }
}

variable "lambda_principals" {
  description = "(Optional) add extra principals to the role created for execution of the lambda, e.g. for local testing."
  type = list(object({
    type        = string
    identifiers = list(string)
  }))
  default = []
}

variable "lambda_s3_bucket" {
  description = "S3 bucket from which to specify lambda functions. This is an alternative to providing local files directly."
  type        = string
  default     = null
}

variable "lambda_s3_key" {
  description = "S3 key for syncer lambda function. Required if using S3 bucket to specify lambdas."
  type        = string
  default     = null
}

variable "lambda_s3_object_version" {
  description = "S3 object version for syncer lambda function. Useful if S3 versioning is enabled on source bucket."
  type        = string
  default     = null
}

variable "lambda_runtime" {
  description = "AWS Lambda runtime."
  type        = string
  default     = "nodejs22.x"
}

variable "lambda_architecture" {
  description = "AWS Lambda architecture. Lambda functions using Graviton processors ('arm64') tend to have better price/performance than 'x86_64' functions. "
  type        = string
  default     = "arm64"
  validation {
    condition     = contains(["arm64", "x86_64"], var.lambda_architecture)
    error_message = "`lambda_architecture` value is not valid, valid values are: `arm64` and `x86_64`."
  }
}

variable "tracing_config" {
  description = "Configuration for lambda tracing."
  type = object({
    mode                  = optional(string, null)
    capture_http_requests = optional(bool, false)
    capture_error         = optional(bool, false)
  })
  default = {}
}

variable "lambda_schedule_expression" {
  description = "Scheduler expression for action runner binary syncer."
  type        = string
  default     = "rate(1 day)"
}

variable "cleanup_config" {
  description = <<EOF
    Configuration for AMI cleanup.

    `amiFilters` - Filters to use when searching for AMIs to cleanup. Default filter for images owned by the account and that are available.
    `dryRun` - If true, no AMIs will be deregistered. Default false.
    `launchTemplateNames` - Launch template names to use when searching for AMIs to cleanup. Default no launch templates.
    `maxItems` - The maximum numer of AMI's tha will be queried for cleanup. Default no maximum.
    `minimumDaysOld` - Minimum number of days old an AMI must be to be considered for cleanup. Default 30.
    `ssmParameterNames` - SSM parameter names to use when searching for AMIs to cleanup. This parameter should be set when using SSM to configure the AMI to use. Default no SSM parameters.
  EOF
  type = object({
    amiFilters = optional(list(object({
      Name   = string
      Values = list(string)
      })),
      [{
        Name : "state",
        Values : ["available"],
        },
        {
          Name : "image-type",
          Values : ["machine"],
      }]
    )
    dryRun              = optional(bool, false)
    launchTemplateNames = optional(list(string))
    maxItems            = optional(number)
    minimumDaysOld      = optional(number, 30)
    ssmParameterNames   = optional(list(string))
  })
  default = {}
}

variable "state_event_rule_ami_housekeeper" {
  type        = string
  description = "State of the rule."
  default     = "ENABLED"

  validation {
    condition     = contains(["ENABLED", "DISABLED", "ENABLED_WITH_ALL_CLOUDTRAIL_MANAGEMENT_EVENTS"], var.state_event_rule_ami_housekeeper)
    error_message = "`state_event_rule_ami_housekeeper` value is not valid, valid values are: `ENABLED`, `DISABLED`, `ENABLED_WITH_ALL_CLOUDTRAIL_MANAGEMENT_EVENTS`."
  }
}

variable "lambda_tags" {
  description = "Map of tags that will be added to all the lambda function resources. Note these are additional tags to the default tags."
  type        = map(string)
  default     = {}
}

variable "lambda_reserved_concurrent_executions" {
  description = "The amount of reserved concurrent executions for this lambda function. A value of 0 disables lambda from being triggered and -1 removes any concurrency limitations."
  type        = number
  default     = -1
}

variable "lambda_dlq_target_arn" {
  description = "The ARN of an SQS queue or SNS topic to use as a dead letter queue for failed asynchronous invocations."
  type        = string
  default     = null
}

variable "lambda_code_signing_config_arn" {
  description = "ARN for a Code Signing Configuration to use for this lambda function."
  type        = string
  default     = null
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