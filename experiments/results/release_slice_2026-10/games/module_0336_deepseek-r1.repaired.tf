resource "aws_cloudwatch_query_definition" "customization_request_query" {
  name = "Account Factory for Terraform/Customization Logs by Customization Request ID"

  log_group_names = [
    "/aws/lambda/${var.create_role_lambda_function_name}",
    "/aws/lambda/${var.persist_metadata_lambda_function_name}",
    "/aws/lambda/${var.tag_account_lambda_function_name}",
    "/aws/lambda/${var.account_metadata_ssm_lambda_function_name}",
    "/aws/lambda/${var.delete_default_vpc_lambda_function_name}",
    "/aws/lambda/${var.enroll_support_lambda_function_name}",
    "/aws/lambda/${var.enable_cloudtrail_lambda_function_name}",
  ]

  query_string = <<EOF
fields @timestamp, log_message.account_id as target_account_id, log_message.customization_request_id as customization_request_id, log_message.detail as detail, @logStream
| sort @timestamp desc
| filter log_message.customization_request_id == "INSERT-CUSTOMIZATION-REQUEST-ID-HERE"
EOF
}

resource "aws_cloudwatch_query_definition" "account_id_query" {
  name = "Account Factory for Terraform/Customization Logs by Account ID"

  log_group_names = [
    "/aws/lambda/${var.create_role_lambda_function_name}",
    "/aws/lambda/${var.persist_metadata_lambda_function_name}",
    "/aws/lambda/${var.tag_account_lambda_function_name}",
    "/aws/lambda/${var.account_metadata_ssm_lambda_function_name}",
    "/aws/lambda/${var.delete_default_vpc_lambda_function_name}",
    "/aws/lambda/${var.enroll_support_lambda_function_name}",
    "/aws/lambda/${var.enable_cloudtrail_lambda_function_name}",
  ]

  query_string = <<EOF
fields @timestamp, log_message.account_id as target_account_id, log_message.customization_request_id as customization_request_id, log_message.detail as detail, @logStream
| sort @timestamp desc
| filter log_message.account_id == "INSERT-ACCOUNT-ID-HERE" and @message like /customization_request_id/
EOF
}

data "aws_partition" "current" {}
data "aws_region" "aft_management" {}
data "aws_caller_identity" "aft_management" {}
data "aws_iam_policy" "AWSLambdaBasicExecutionRole" {
  name = "AWSLambdaBasicExecutionRole"
}

data "aws_iam_policy" "AWSLambdaVPCAccessExecutionRole" {
  name = "AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role" "aft_lambda_aft_account_provisioning_framework_create_role" {
  name               = "aft-account-provisioning-framework-lambda-create-role-role"
  assume_role_policy = templatefile("${path.module}/iam/trust-policies/lambda.tpl", { none = "none" })
}

resource "aws_iam_role_policy_attachment" "aft_account_provisioning_framework_create_role" {
  count      = length(local.lambda_managed_policies)
  role       = aws_iam_role.aft_lambda_aft_account_provisioning_framework_create_role.name
  policy_arn = local.lambda_managed_policies[count.index]
}

resource "aws_iam_role_policy" "aft_invoke_aft_account_provisioning_framework_create_role" {
  name = "aft-lambda-invoke-aft_account_provisioning_framework-create-role-policy"
  role = aws_iam_role.aft_lambda_aft_account_provisioning_framework_create_role.id
  policy = templatefile("${path.module}/iam/role-policies/lambda-aft-account-provisioning-framework.tpl", {
    data_aws_partition_current_partition               = data.aws_partition.current.partition
    data_aws_region_aft-management_name                = data.aws_region.aft_management.region
    data_aws_caller_identity_aft-management_account_id = data.aws_caller_identity.aft_management.account_id
    aft_sns_topic_arn                                  = var.aft_sns_topic_arn
    aft_failure_sns_topic_arn                          = var.aft_failure_sns_topic_arn
    aws_kms_key_aft_arn                                = var.aft_kms_key_arn
  })
}

resource "aws_iam_role" "aft_lambda_aft_account_provisioning_framework_tag_account" {
  name               = "aft-account-provisioning-framework-lambda-tag-account-role"
  assume_role_policy = templatefile("${path.module}/iam/trust-policies/lambda.tpl", { none = "none" })
}

resource "aws_iam_role_policy_attachment" "aft_account_provisioning_framework_tag_account" {
  count      = length(local.lambda_managed_policies)
  role       = aws_iam_role.aft_lambda_aft_account_provisioning_framework_tag_account.name
  policy_arn = local.lambda_managed_policies[count.index]
}

resource "aws_iam_role_policy" "aft_invoke_aft_account_provisioning_framework_tag_account" {
  name = "aft-lambda-invoke-aft-account-provisioning-framework-tag-account-policy"
  role = aws_iam_role.aft_lambda_aft_account_provisioning_framework_tag_account.id
  policy = templatefile("${path.module}/iam/role-policies/lambda-aft-account-provisioning-framework.tpl", {
    data_aws_partition_current_partition               = data.aws_partition.current.partition
    data_aws_region_aft-management_name                = data.aws_region.aft_management.region
    data_aws_caller_identity_aft-management_account_id = data.aws_caller_identity.aft_management.account_id
    aft_sns_topic_arn                                  = var.aft_sns_topic_arn
    aft_failure_sns_topic_arn                          = var.aft_failure_sns_topic_arn
    aws_kms_key_aft_arn                                = var.aft_kms_key_arn
  })
}

resource "aws_iam_role" "aft_lambda_aft_account_provisioning_framework_persist_metadata" {
  name               = "aft-account-provisioning-framework-lambda-persist-metadata-role"
  assume_role_policy = templatefile("${path.module}/iam/trust-policies/lambda.tpl", { none = "none" })
}

resource "aws_iam_role_policy_attachment" "aft_account_provisioning_framework_persist_metadata" {
  count      = length(local.lambda_managed_policies)
  role       = aws_iam_role.aft_lambda_aft_account_provisioning_framework_persist_metadata.name
  policy_arn = local.lambda_managed_policies[count.index]
}

resource "aws_iam_role_policy" "aft_invoke_aft_account_provisioning_framework_persist_metadata" {
  name = "aft-lambda-invoke-aft-account-provisioning-framework-persist-metadata-policy"
  role = aws_iam_role.aft_lambda_aft_account_provisioning_framework_persist_metadata.id
  policy = templatefile("${path.module}/iam/role-policies/lambda-aft-account-provisioning-framework.tpl", {
    data_aws_partition_current_partition               = data.aws_partition.current.partition
    data_aws_region_aft-management_name                = data.aws_region.aft_management.region
    data_aws_caller_identity_aft-management_account_id = data.aws_caller_identity.aft_management.account_id
    aft_sns_topic_arn                                  = var.aft_sns_topic_arn
    aft_failure_sns_topic_arn                          = var.aft_failure_sns_topic_arn
    aws_kms_key_aft_arn                                = var.aft_kms_key_arn
  })
}

resource "aws_iam_role" "aft_states" {
  name               = "aft-states-execution-role"
  assume_role_policy = templatefile("${path.module}/iam/trust-policies/states.tpl", { none = "none" })
}

resource "aws_iam_role_policy" "aft_states" {
  name = "aft-account-provisioning-framework-states-policy"
  role = aws_iam_role.aft_states.id

  policy = templatefile("${path.module}/iam/role-policies/iam-aft-states.tpl", {
    data_aws_partition_current_partition               = data.aws_partition.current.partition
    data_aws_region_aft-management_name                = data.aws_region.aft_management.region
    data_aws_caller_identity_aft-management_account_id = data.aws_caller_identity.aft_management.account_id
    aws_kms_key_aft_arn                                = var.aft_kms_key_arn
    sns_topic_enable_cmk_encryption                    = var.sns_topic_enable_cmk_encryption
  })
}

resource "aws_lambda_function" "create_role" {
  filename                       = var.provisioning_framework_archive_path
  function_name                  = var.create_role_lambda_function_name
  description                    = "AFT account provisioning framework - create_role"
  role                           = aws_iam_role.aft_lambda_aft_account_provisioning_framework_create_role.arn
  handler                        = "aft_account_provisioning_framework_create_role.lambda_handler"
  source_code_hash               = var.provisioning_framework_archive_hash
  memory_size                    = 1024
  runtime                        = var.lambda_runtime_python_version
  timeout                        = 300
  layers                         = [var.aft_common_layer_arn]
  reserved_concurrent_executions = 100
  tracing_config {
    mode = "Active"
  }
  dead_letter_config {
    target_arn = var.aft_failure_sns_topic_arn
  }

  dynamic "vpc_config" {
    for_each = var.aft_enable_vpc ? [1] : []
    content {
      subnet_ids         = var.aft_vpc_private_subnets
      security_group_ids = var.aft_vpc_default_sg
    }
  }
}

resource "aws_cloudwatch_log_group" "create_role" {
  name              = "/aws/lambda/${aws_lambda_function.create_role.function_name}"
  retention_in_days = var.cloudwatch_log_group_retention
  kms_key_id        = var.cloudwatch_log_group_enable_cmk_encryption ? var.aft_kms_key_arn : null
}

resource "aws_lambda_function" "tag_account" {
  filename                       = var.provisioning_framework_archive_path
  function_name                  = var.tag_account_lambda_function_name
  description                    = "AFT account provisioning framework - tag_account"
  role                           = aws_iam_role.aft_lambda_aft_account_provisioning_framework_tag_account.arn
  handler                        = "aft_account_provisioning_framework_tag_account.lambda_handler"
  source_code_hash               = var.provisioning_framework_archive_hash
  memory_size                    = 1024
  runtime                        = var.lambda_runtime_python_version
  timeout                        = 300
  layers                         = [var.aft_common_layer_arn]
  reserved_concurrent_executions = 100
  tracing_config {
    mode = "Active"
  }
  dead_letter_config {
    target_arn = var.aft_failure_sns_topic_arn
  }

  dynamic "vpc_config" {
    for_each = var.aft_enable_vpc ? [1] : []
    content {
      subnet_ids         = var.aft_vpc_private_subnets
      security_group_ids = var.aft_vpc_default_sg
    }
  }
}

resource "aws_cloudwatch_log_group" "tag_account" {
  name              = "/aws/lambda/${aws_lambda_function.tag_account.function_name}"
  retention_in_days = var.cloudwatch_log_group_retention
  kms_key_id        = var.cloudwatch_log_group_enable_cmk_encryption ? var.aft_kms_key_arn : null
}

resource "aws_lambda_function" "persist_metadata" {
  filename                       = var.provisioning_framework_archive_path
  function_name                  = var.persist_metadata_lambda_function_name
  description                    = "AFT account provisioning framework - persist_metadata"
  role                           = aws_iam_role.aft_lambda_aft_account_provisioning_framework_persist_metadata.arn
  handler                        = "aft_account_provisioning_framework_persist_metadata.lambda_handler"
  source_code_hash               = var.provisioning_framework_archive_hash
  memory_size                    = 1024
  runtime                        = var.lambda_runtime_python_version
  timeout                        = 300
  layers                         = [var.aft_common_layer_arn]
  reserved_concurrent_executions = 100
  tracing_config {
    mode = "Active"
  }
  dead_letter_config {
    target_arn = var.aft_failure_sns_topic_arn
  }

  dynamic "vpc_config" {
    for_each = var.aft_enable_vpc ? [1] : []
    content {
      subnet_ids         = var.aft_vpc_private_subnets
      security_group_ids = var.aft_vpc_default_sg
    }
  }
}

resource "aws_cloudwatch_log_group" "persist_metadata" {
  name              = "/aws/lambda/${aws_lambda_function.persist_metadata.function_name}"
  retention_in_days = var.cloudwatch_log_group_retention
  kms_key_id        = var.cloudwatch_log_group_enable_cmk_encryption ? var.aft_kms_key_arn : null
}

resource "aws_lambda_function" "account_metadata_ssm" {
  filename                       = var.provisioning_framework_archive_path
  function_name                  = var.account_metadata_ssm_lambda_function_name
  description                    = "AFT account provisioning framework - account_metadata_ssm"
  role                           = aws_iam_role.aft_lambda_aft_account_provisioning_framework_persist_metadata.arn
  handler                        = "aft_account_provisioning_framework_account_metadata_ssm.lambda_handler"
  source_code_hash               = var.provisioning_framework_archive_hash
  memory_size                    = 1024
  runtime                        = var.lambda_runtime_python_version
  timeout                        = 300
  layers                         = [var.aft_common_layer_arn]
  reserved_concurrent_executions = 100
  tracing_config {
    mode = "Active"
  }
  dead_letter_config {
    target_arn = var.aft_failure_sns_topic_arn
  }

  dynamic "vpc_config" {
    for_each = var.aft_enable_vpc ? [1] : []
    content {
      subnet_ids         = var.aft_vpc_private_subnets
      security_group_ids = var.aft_vpc_default_sg
    }
  }
}

resource "aws_cloudwatch_log_group" "account_metadata_ssm" {
  name              = "/aws/lambda/${aws_lambda_function.account_metadata_ssm.function_name}"
  retention_in_days = var.cloudwatch_log_group_retention
  kms_key_id        = var.cloudwatch_log_group_enable_cmk_encryption ? var.aft_kms_key_arn : null
}

locals {
  lambda_managed_policies = [data.aws_iam_policy.AWSLambdaBasicExecutionRole.arn, data.aws_iam_policy.AWSLambdaVPCAccessExecutionRole.arn]
}

output "state_machine_arn" {
  value = aws_sfn_state_machine.aft_account_provisioning_framework_sfn.arn
}

output "create_role_function_arn" {
  value = aws_lambda_function.create_role.arn
}
output "tag_account_function_arn" {
  value = aws_lambda_function.tag_account.arn
}
output "persist_metadata_function_arn" {
  value = aws_lambda_function.persist_metadata.arn
}

locals {
  state_machine_source = "${path.module}/states/aft_account_provisioning_framework.asl.json"
  replacements_map = {
    current_partition                                                 = data.aws_partition.current.partition
    create_role_function_name                                         = aws_lambda_function.create_role.function_name
    tag_account_function_name                                         = aws_lambda_function.tag_account.function_name
    persist_metadata_function_name                                    = aws_lambda_function.persist_metadata.function_name
    account_metadata_ssm_function_name                                = aws_lambda_function.account_metadata_ssm.function_name
    aft_notification_arn                                              = var.aft_sns_topic_arn
    aft_failure_notification_arn                                      = var.aft_failure_sns_topic_arn
    aft_account_provisioning_customizations_state_machine_arn         = "arn:${data.aws_partition.current.partition}:states:${data.aws_region.aft_management.region}:${data.aws_caller_identity.aft_management.account_id}:stateMachine:${var.aft_account_provisioning_customizations_sfn_name}"
    customizations_trigger_state_machine_arn                          = "arn:${data.aws_partition.current.partition}:states:${data.aws_region.aft_management.region}:${data.aws_caller_identity.aft_management.account_id}:stateMachine:${var.trigger_customizations_sfn_name}"
    aft_account_provisioning_framework_aft_features_state_machine_arn = "arn:${data.aws_partition.current.partition}:states:${data.aws_region.aft_management.region}:${data.aws_caller_identity.aft_management.account_id}:stateMachine:${var.aft_features_sfn_name}"
  }
}

resource "aws_sfn_state_machine" "aft_account_provisioning_framework_sfn" {
  name       = var.aft_account_provisioning_framework_sfn_name
  role_arn   = aws_iam_role.aft_states.arn
  definition = templatefile(local.state_machine_source, local.replacements_map)
  tracing_configuration {
    enabled = true
  }
  logging_configuration {
    level                  = "ALL"
    include_execution_data = true
    log_destination        = "arn:${data.aws_partition.current.partition}:logs:${data.aws_region.aft_management.region}:${data.aws_caller_identity.aft_management.account_id}:log-group:/aws/vendedlogs/states/${var.aft_account_provisioning_framework_sfn_name}-logs:*"
  }
}

variable "aft_account_provisioning_framework_sfn_name" {
  type = string
}

variable "aft_sns_topic_arn" {
  type = string
}

variable "aft_failure_sns_topic_arn" {
  type = string
}

variable "aft_common_layer_arn" {
  type = string
}

variable "aft_kms_key_arn" {
  type = string
}

variable "cloudwatch_log_group_retention" {
  type = string
}

variable "cloudwatch_log_group_enable_cmk_encryption" {
  type = bool
}

variable "aft_account_provisioning_customizations_sfn_name" {
  type = string
}

variable "trigger_customizations_sfn_name" {
  type = string
}

variable "aft_features_sfn_name" {
  type = string
}

variable "aft_vpc_private_subnets" {
  type    = list(string)
  default = null
}

variable "aft_vpc_default_sg" {
  type    = list(string)
  default = null
}

variable "provisioning_framework_archive_path" {
  type = string
}

variable "provisioning_framework_archive_hash" {
  type = string
}

variable "create_role_lambda_function_name" {
  type = string
}

variable "tag_account_lambda_function_name" {
  type = string
}

variable "persist_metadata_lambda_function_name" {
  type = string
}

variable "account_metadata_ssm_lambda_function_name" {
  type = string
}

variable "delete_default_vpc_lambda_function_name" {
  type = string
}

variable "enroll_support_lambda_function_name" {
  type = string
}

variable "enable_cloudtrail_lambda_function_name" {
  type = string
}

variable "lambda_runtime_python_version" {
  type = string
}

variable "aft_enable_vpc" {
  type = bool
}

variable "sns_topic_enable_cmk_encryption" {
  type = bool
}

terraform {
  required_version = ">= 1.2.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0.0, < 7.0.0"
    }
  }
}