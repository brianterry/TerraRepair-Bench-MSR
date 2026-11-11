resource "aws_lambda_function" "local_zipfile" {
  count = "${var.function_s3_bucket == "" ? 1 : 0}"

  filename         = "${var.function_zipfile}"
  source_code_hash = "${var.function_s3_bucket == "" ? "${base64sha256(file("${var.function_zipfile}"))}" : ""}"

  description   = "${var.comment_prefix}${var.cronjob_name}"
  function_name = "${local.prefix_with_name}"
  handler       = "${var.function_handler}"
  runtime       = "${var.function_runtime}"
  timeout       = "${var.function_timeout}"
  memory_size   = "${var.memory_size}"
  role          = "${aws_iam_role.this.arn}"
  tags          = "${var.tags}"

  reserved_concurrent_executions = "${var.reserved_concurrent_executions}"
  code_signing_config_arn        = "${var.code_signing_config_arn}"

  dead_letter_config {
    target_arn = "${var.dead_letter_target_arn}"
  }

  tracing_config {
    mode = "Active"
  }

  vpc_config {
    subnet_ids         = "${var.subnet_ids}"
    security_group_ids = "${var.security_group_ids}"
  }

  environment {
    variables = "${var.function_env_vars}"
  }

  kms_key_arn = "${var.kms_key_arn}"
}

resource "aws_lambda_function" "s3_zipfile" {
  count = "${var.function_s3_bucket == "" ? 0 : 1}"

  s3_bucket = "${var.function_s3_bucket}"
  s3_key    = "${var.function_zipfile}"

  description   = "${var.comment_prefix}${var.cronjob_name}"
  function_name = "${local.prefix_with_name}"
  handler       = "${var.function_handler}"
  runtime       = "${var.function_runtime}"
  timeout       = "${var.function_timeout}"
  memory_size   = "${var.memory_size}"
  role          = "${aws_iam_role.this.arn}"
  tags          = "${var.tags}"

  reserved_concurrent_executions = "${var.reserved_concurrent_executions}"
  code_signing_config_arn        = "${var.code_signing_config_arn}"

  dead_letter_config {
    target_arn = "${var.dead_letter_target_arn}"
  }

  tracing_config {
    mode = "Active"
  }

  vpc_config {
    subnet_ids         = "${var.subnet_ids}"
    security_group_ids = "${var.security_group_ids}"
  }

  environment {
    variables = "${var.function_env_vars}"
  }

  kms_key_arn = "${var.kms_key_arn}"
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


resource "aws_iam_role" "this" {
  name = "${local.prefix_with_name}"
  tags = "${var.tags}"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": [
          "lambda.amazonaws.com"
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
  name  = "${local.prefix_with_name}"

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

resource "aws_cloudwatch_event_rule" "this" {
  name                = "${local.prefix_with_name}---scheduled-invocation"
  schedule_expression = "${var.schedule_expression}"
  tags                = "${var.tags}"
}

resource "aws_cloudwatch_event_target" "this" {
  rule      = "${aws_cloudwatch_event_rule.this.name}"
  target_id = "${aws_cloudwatch_event_rule.this.name}"
  arn       = "${local.function_arn}"
}

resource "aws_lambda_permission" "this" {
  statement_id  = "${local.prefix_with_name}---scheduled-invocation"
  action        = "lambda:InvokeFunction"
  function_name = "${local.function_id}"
  principal     = "events.amazonaws.com"
  source_arn    = "${aws_cloudwatch_event_rule.this.arn}"
}


variable "cronjob_name" {
  description = "Name which will be used to create your Lambda function (e.g. `\"my-important-cronjob\"`)"
}

variable "name_prefix" {
  description = "Name prefix to use for objects that need to be created (only lowercase alphanumeric characters and hyphens allowed, for S3 bucket name compatibility)"
  default     = "aws-lambda-cronjob---"
}

variable "comment_prefix" {
  description = "This will be included in comments for resources that are created"
  default     = "Lambda Cronjob: "
}

variable "schedule_expression" {
  description = "How often to run the Lambda (see https://docs.aws.amazon.com/AmazonCloudWatch/latest/events/ScheduledEvents.html); e.g. `\"rate(15 minutes)\"` or `\"cron(0 12 * * ? *)\"`"
  default     = "rate(60 minutes)"
}

variable "function_zipfile" {
  description = "Path to a ZIP file that will be installed as the Lambda function (e.g. `\"my-cronjob.zip\"`)"
}

variable "function_s3_bucket" {
  description = "When provided, the zipfile is retrieved from an S3 bucket by this name instead (filename is still provided via `function_zipfile`)"
  default     = ""
}

variable "function_handler" {
  description = "Instructs Lambda on which function to invoke within the ZIP file"
  default     = "index.handler"
}

variable "function_timeout" {
  description = "The amount of time your Lambda Function has to run in seconds"
  default     = 3
}

variable "memory_size" {
  description = "Amount of memory in MB your Lambda Function can use at runtime"
  default     = 128
}

variable "function_runtime" {
  description = "Which node.js version should Lambda use for this function"
  default     = "nodejs20.x"
}

variable "function_env_vars" {
  description = "Which env vars (if any) to invoke the Lambda with"
  type        = "map"

  default = {
    aws_lambda_cronjob = ""
  }
}

variable "lambda_logging_enabled" {
  description = "When true, writes any console output to the Lambda function's CloudWatch group"
  default     = false
}

variable "tags" {
  description = "AWS Tags to add to all resources created (where possible); see https://aws.amazon.com/answers/account-management/aws-tagging-strategies/"
  type        = "map"
  default     = {}
}

variable "reserved_concurrent_executions" {
  description = "The amount of reserved concurrent executions for this lambda function"
  default     = -1
}

variable "dead_letter_target_arn" {
  description = "The ARN of an SNS topic or SQS queue to notify when an invocation fails"
}

variable "kms_key_arn" {
  description = "The ARN of the KMS key used to encrypt environment variables"
}

variable "code_signing_config_arn" {
  description = "The ARN of the code signing configuration"
}

variable "subnet_ids" {
  description = "List of subnet IDs associated with the Lambda function"
  type        = "list"
}

variable "security_group_ids" {
  description = "List of security group IDs associated with the Lambda function"
  type        = "list"
}

locals {
  prefix_with_name = "${var.name_prefix}${replace("${var.cronjob_name}", "/[^a-z0-9-]+/", "-")}"
}