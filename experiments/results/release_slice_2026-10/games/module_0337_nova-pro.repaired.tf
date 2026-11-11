data "aws_availability_zones" "available" {
  state = "available"
  names = [
    "us-east-1a",
    "us-east-1b",
    "us-east-1c",
    "us-east-1d",
    "us-east-1e",
    "us-east-1f",
    "us-west-1a",
    "us-west-1b",
    "us-west-1c",
    "us-west-2a",
    "us-west-2b",
    "us-west-2c",
    "ap-south-1a",
    "ap-south-1b",
    "ap-south-1c",
    "ap-northeast-2a",
    "ap-northeast-2b",
    "ap-northeast-2c",
    "ap-southeast-1a",
    "ap-southeast-1b",
    "ap-southeast-1c",
    "ap-southeast-2a",
    "ap-southeast-2b",
    "ap-southeast-2c",
    "ap-northeast-1a",
    "ap-northeast-1b",
    "ap-northeast-1c",
    "ca-central-1a",
    "ca-central-1b",
    "eu-central-1a",
    "eu-central-1b",
    "eu-west-1a",
    "eu-west-1b",
    "eu-west-1c",
    "eu-west-2a",
    "eu-west-2b",
    "eu-west-2c",
    "eu-west-3a",
    "eu-west-3b",
    "eu-west-3c",
    "sa-east-1a",
    "sa-east-1b",
    "sa-east-1c",
  ]
}

resource "aws_lambda_function" "aft_account_request_audit_trigger" {
  filename      = var.request_framework_archive_path
  function_name = "aft-account-request-audit-trigger"
  description   = "Receives trigger from DynamoDB aft-request table and inserts the event into aft-request-audit table"
  role          = aws_iam_role.aft_account_request_audit_trigger.arn
  handler       = "aft_account_request_audit_trigger.lambda_handler"
  source_code_hash = var.request_framework_archive_hash
  memory_size      = 1024
  runtime          = var.lambda_runtime_python_version
  timeout          = "300"
  layers           = [var.aft_common_layer_arn]
  reserved_concurrent_executions = 1
  tracing_config {
    mode = "Active"
  }
  dynamic "vpc_config" {
    for_each = local.vpc_deployment? [1] : []
    content {
      subnet_ids         = local.vpc_private_subnet_ids
      security_group_ids = tolist([aws_security_group.aft_vpc_default_sg[0].id])
    }
  }
  dead_letter_config {
    target_arn = aws_sqs_queue.aft_account_request_dlq.arn
  }
  environment {
    variables = {
      AWS_LAMBDA_EXEC_WRAPPER = "/opt/code-signing-wrapper"
    }
  }
}

resource "aws_lambda_function" "aft_account_request_action_trigger" {
  filename      = var.request_framework_archive_path
  function_name = "aft-account-request-action-trigger"
  description   = "Receives trigger from DynamoDB aft-request table and determines action target - SQS or Lambda aft-invoke-aft-account-provisioning-framework"
  role          = aws_iam_role.aft_account_request_action_trigger.arn
  handler       = "aft_account_request_action_trigger.lambda_handler"
  source_code_hash = var.request_framework_archive_hash
  memory_size      = 1024
  runtime          = var.lambda_runtime_python_version
  timeout          = "600"
  layers           = [var.aft_common_layer_arn]
  reserved_concurrent_executions = 1
  tracing_config {
    mode = "Active"
  }
  dynamic "vpc_config" {
    for_each = local.vpc_deployment? [1] : []
    content {
      subnet_ids         = local.vpc_private_subnet_ids
      security_group_ids = tolist([aws_security_group.aft_vpc_default_sg[0].id])
    }
  }
  dead_letter_config {
    target_arn = aws_sqs_queue.aft_account_request_dlq.arn
  }
  environment {
    variables = {
      AWS_LAMBDA_EXEC_WRAPPER = "/opt/code-signing-wrapper"
    }
  }
}

resource "aws_lambda_function" "aft_controltower_event_logger" {
  filename      = var.request_framework_archive_path
  function_name = "aft-controltower-event-logger"
  description   = "Receives Control Tower events through dedicated event bus event and writes event to aft-controltower-events table"
  role          = aws_iam_role.aft_controltower_event_logger.arn
  handler       = "aft_controltower_event_logger.lambda_handler"
  source_code_hash = var.request_framework_archive_hash
  memory_size      = 1024
  runtime          = var.lambda_runtime_python_version
  timeout          = "300"
  layers           = [var.aft_common_layer_arn]
  reserved_concurrent_executions = 1
  tracing_config {
    mode = "Active"
  }
  dynamic "vpc_config" {
    for_each = local.vpc_deployment? [1] : []
    content {
      subnet_ids         = local.vpc_private_subnet_ids
      security_group_ids = tolist([aws_security_group.aft_vpc_default_sg[0].id])
    }
  }
  dead_letter_config {
    target_arn = aws_sqs_queue.aft_account_request_dlq.arn
  }
  environment {
    variables = {
      AWS_LAMBDA_EXEC_WRAPPER = "/opt/code-signing-wrapper"
    }
  }
}

resource "aws_lambda_function" "aft_account_request_processor" {
  filename      = var.request_framework_archive_path
  function_name = "aft-account-request-processor"
  description   = "Triggered by CW Event, reads aft-account-request.fifo queue and performs needed action"
  role          = aws_iam_role.aft_account_request_processor.arn
  handler       = "aft_account_request_processor.lambda_handler"
  source_code_hash = var.request_framework_archive_hash
  memory_size      = 1024
  runtime          = var.lambda_runtime_python_version
  timeout          = "300"
  layers           = [var.aft_common_layer_arn]
  reserved_concurrent_executions = 1
  tracing_config {
    mode = "Active"
  }
  dynamic "vpc_config" {
    for_each = local.vpc_deployment? [1] : []
    content {
      subnet_ids         = local.vpc_private_subnet_ids
      security_group_ids = tolist([aws_security_group.aft_vpc_default_sg[0].id])
    }
  }
  dead_letter_config {
    target_arn = aws_sqs_queue.aft_account_request_dlq.arn
  }
  environment {
    variables = {
      AFT_PROVISIONING_CONCURRENCY = var.concurrent_account_factory_actions
      AWS_LAMBDA_EXEC_WRAPPER = "/opt/code-signing-wrapper"
    }
  }
}

resource "aws_lambda_function" "aft_invoke_aft_account_provisioning_framework" {
  filename      = var.request_framework_archive_path
  function_name = "aft-invoke-aft-account-provisioning-framework"
  description   = "Calls AFT Account Provisioning Framework Step Function based on a formatted incoming event from Lambda or CW Event"
  role          = aws_iam_role.aft_invoke_aft_account_provisioning_framework.arn
  handler       = "aft_invoke_aft_account_provisioning_framework.lambda_handler"
  source_code_hash = var.request_framework_archive_hash
  memory_size      = 1024
  runtime          = var.lambda_runtime_python_version
  timeout          = "300"
  layers           = [var.aft_common_layer_arn]
  reserved_concurrent_executions = 1
  tracing_config {
    mode = "Active"
  }
  dynamic "vpc_config" {
    for_each = local.vpc_deployment? [1] : []
    content {
      subnet_ids         = local.vpc_private_subnet_ids
      security_group_ids = tolist([aws_security_group.aft_vpc_default_sg[0].id])
    }
  }
  dead_letter_config {
    target_arn = aws_sqs_queue.aft_account_request_dlq.arn
  }
  environment {
    variables = {
      AWS_LAMBDA_EXEC_WRAPPER = "/opt/code-signing-wrapper"
    }
  }
}

resource "aws_lambda_function" "aft_cleanup_resources" {
  filename      = var.request_framework_archive_path
  function_name = "aft-cleanup-resources"
  description   = "Removes AFT pipeline resources when an account record is removed from the AFT repo"
  role          = aws_iam_role.aft_cleanup_resources.arn
  handler       = "aft_cleanup_resources.lambda_handler"
  source_code_hash = var.request_framework_archive_hash
  memory_size      = 1024
  runtime          = var.lambda_runtime_python_version
  timeout          = "300"
  layers           = [var.aft_common_layer_arn]
  reserved_concurrent_executions = 1
  tracing_config {
    mode = "Active"
  }
  dynamic "vpc_config" {
    for_each = local.vpc_deployment? [1] : []
    content {
      subnet_ids         = local.vpc_private_subnet_ids
      security_group_ids = tolist([aws_security_group.aft_vpc_default_sg[0].id])
    }
  }
  dead_letter_config {
    target_arn = aws_sqs_queue.aft_account_request_dlq.arn
  }
  environment {
    variables = {
      AWS_LAMBDA_EXEC_WRAPPER = "/opt/code-signing-wrapper"
    }
  }
}

resource "aws_security_group" "aft_vpc_default_sg" {
  count       = var.aft_enable_vpc || var.aft_customer_vpc_id!= null? 1 : 0
  name        = "aft-default-sg"
  description = "Allow outbound traffic"
  vpc_id      = local.vpc_id
  egress {
    from_port        = 0
    to_port          = 65535
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
}

resource "aws_security_group" "aft_vpc_endpoint_sg" {
  count       = var.aft_enable_vpc || var.aft_customer_vpc_id!= null? 1 : 0
  name        = "aft-endpoint-sg"
  description = "Allow inbound HTTPS traffic and all Outbound"
  vpc_id      = local.vpc_id
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [local.vpc_cidr]
  }
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [local.vpc_cidr]
  }
  egress {
    from_port        = 0
    to_port          = 65535
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
}

resource "aws_vpc_flow_log" "aft_vpc" {
  vpc_id         = aws_vpc.aft_vpc[0].id
  iam_role_arn   = aws_iam_role.aft_vpc_flow_logs.arn
  traffic_type   = "ALL"
  depends_on     = [aws_vpc.aft_vpc]
  destination_options = "file_format=parquet"
}