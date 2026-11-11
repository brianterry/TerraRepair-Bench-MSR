# Copyright Amazon.com, Inc. or its affiliates. All rights reserved.
# SPDX-License-Identifier: Apache-2.0
#

resource "aws_cloudwatch_log_group" "codebuild_loggroup" {
  name              = "/aws/codebuild/${local.common_name}"
  retention_in_days = var.cloudwatch_log_group_retention
  kms_key_id        = var.cloudwatch_log_group_enable_cmk_encryption ? var.aft_kms_key_arn : null
}

resource "aws_codebuild_project" "codebuild" {
  name           = local.common_name
  description    = "Codebuild project to create lambda layer ${var.lambda_layer_name}"
  build_timeout  = "10"
  service_role   = aws_iam_role.codebuild.arn
  encryption_key = var.aft_kms_key_arn

  artifacts {
    type = "NO_ARTIFACTS"
  }

  environment {
    compute_type                = var.codebuild_compute_type
    image                       = "aws/codebuild/amazonlinux2-x86_64-standard:5.0"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"

    environment_variable {
      name  = "PYTHON_VERSION"
      value = var.lambda_layer_python_version
    }
    environment_variable {
      name  = "BUCKET_NAME"
      value = var.s3_bucket_name
    }
    environment_variable {
      name  = "SSM_AWS_MODULE_SOURCE"
      value = var.aft_tf_aws_customizations_module_url_ssm_path
      type  = "PLAINTEXT"
    }
    environment_variable {
      name  = "SSM_AWS_MODULE_GIT_REF"
      value = var.aft_tf_aws_customizations_module_git_ref_ssm_path
      type  = "PLAINTEXT"
    }

  }

  logs_config {
    cloudwatch_logs {
      group_name  = aws_cloudwatch_log_group.codebuild_loggroup.name
      stream_name = "build-logs"
    }

    s3_logs {
      status   = "ENABLED"
      location = "${var.s3_bucket_name}/aft-lambda-layer-builder-logs"
    }
  }

  source {
    type      = "NO_SOURCE"
    buildspec = data.local_file.aft_lambda_layer.content
  }

  dynamic "vpc_config" {
    for_each = var.aft_enable_vpc ? [1] : []
    content {
      vpc_id             = var.aft_vpc_id
      subnets            = var.aft_vpc_private_subnets
      security_group_ids = var.aft_vpc_default_sg
    }
  }

  lifecycle {
    ignore_changes = [project_visibility]
  }

}


# Copyright Amazon.com, Inc. or its affiliates. All rights reserved.
# SPDX-License-Identifier: Apache-2.0
#
data "aws_partition" "current" {}

data "aws_caller_identity" "session" {}

data "local_file" "aft_lambda_layer" {
  filename = "${path.module}/buildspecs/aft-lambda-layer.yml"
}


# Copyright Amazon.com, Inc. or its affiliates. All rights reserved.
# SPDX-License-Identifier: Apache-2.0
#
resource "aws_iam_role" "codebuild" {
  name               = local.common_name
  assume_role_policy = file("${path.module}/iam/trust-policies/codebuild.tpl")
}

resource "aws_iam_role" "codebuild_trigger_lambda_role" {
  name               = "codebuild_trigger_role"
  assume_role_policy = file("${path.module}/iam/trust-policies/lambda.tpl")
}

resource "aws_iam_role_policy" "codebuild" {
  role = aws_iam_role.codebuild.name
  policy = templatefile("${path.module}/iam/role-policies/codebuild.tpl", {
    "data_aws_partition_current_partition"      = data.aws_partition.current.partition
    "aws_region"                                = var.aws_region
    "account_id"                                = local.account_id
    "layer_name"                                = var.lambda_layer_name
    "s3_bucket_name"                            = var.s3_bucket_name
    "data_aws_kms_alias_aft_key_target_key_arn" = var.aft_kms_key_arn
  })
}

resource "aws_iam_role_policy" "codebuild_trigger_policy" {
  role = aws_iam_role.codebuild_trigger_lambda_role.name
  policy = templatefile("${path.module}/iam/role-policies/codebuild-trigger.tpl", {
    "data_aws_partition_current_partition" = data.aws_partition.current.partition
    "aws_region"                           = var.aws_region
    "account_id"                           = local.account_id
    "codebuild_project_name"               = aws_codebuild_project.codebuild.name
    "codebuild_trigger_function_name"      = local.codebuild_trigger_function_name
  })
}

resource "aws_iam_role_policy_attachment" "codebuild_trigger_VPC_access" {
  role       = aws_iam_role.codebuild_trigger_lambda_role.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy_attachment" "codebuild_trigger_XRay_access" {
  role       = aws_iam_role.codebuild_trigger_lambda_role.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

resource "aws_iam_role_policy_attachment" "codebuild_trigger_code_signing" {
  role       = aws_iam_role.codebuild_trigger_lambda_role.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMReadOnlyAccess"
}

resource "aws_sqs_queue" "codebuild_trigger_dead_letter_queue" {
  name                        = "codebuild-trigger-dead-letter-queue"
  delay_seconds               = 90
  message_retention_period    = 86400
  receive_wait_time_seconds   = 20
  visibility_timeout_seconds  = 300
}

resource "aws_lambda_function" "codebuild_trigger" {
  filename         = var.builder_archive_path
  function_name    = local.codebuild_trigger_function_name
  description      = "AFT Lambda Layer - CodeBuild Trigger"
  role             = aws_iam_role.codebuild_trigger_lambda_role.arn
  handler          = "codebuild_trigger.lambda_handler"
  source_code_hash = var.builder_archive_hash
  memory_size      = 1024
  runtime          = var.lambda_runtime_python_version
  timeout          = 900
  reserved_concurrent_executions = 1
  tracing_config {
    mode = "Active"
  }
  dead_letter_config {
    target_arn = aws_sqs_queue.codebuild_trigger_dead_letter_queue.arn
  }
  dynamic "vpc_config" {
    for_each = var.aft_enable_vpc ? [1] : []
    content {
      subnet_ids         = var.aft_vpc_private_subnets
      security_group_ids = var.aft_vpc_default_sg
    }
  }
}

resource "aws_lambda_function_url" "codebuild_trigger_url" {
  function_name      = aws_lambda_function.codebuild_trigger.function_name
  authorization_type = "NONE"
}

resource "aws_cloudwatch_log_group" "codebuild_trigger_loggroup" {
  name              = "/aws/lambda/${aws_lambda_function.codebuild_trigger.function_name}"
  retention_in_days = var.cloudwatch_log_group_retention
  kms_key_id        = var.cloudwatch_log_group_enable_cmk_encryption ? var.aft_kms_key_arn : null
}

data "aws_lambda_invocation" "trigger_codebuild_job" {
  function_name = aws_lambda_function.codebuild_trigger.function_name

  input = <<JSON
{
  "codebuild_project_name": "${aws_codebuild_project.codebuild.name}"
}
JSON
}

output "lambda_layer_build_status" {
  value = jsondecode(data.aws_lambda_invocation.trigger_codebuild_job.result)["Status"]
}


# Copyright Amazon.com, Inc. or its affiliates. All rights reserved.
# SPDX-License-Identifier: Apache-2.0
#
locals {
  common_name                     = "python-layer-builder-${var.lambda_layer_name}-${random_string.resource_suffix.result}"
  account_id                      = data.aws_caller_identity.session.account_id
  codebuild_trigger_function_name = "aft-lambda-layer-codebuild-trigger"
}


# Copyright Amazon.com, Inc. or its affiliates. All rights reserved.
# SPDX-License-Identifier: Apache-2.0
#
resource "random_string" "resource_suffix" {
  length  = "8"
  lower   = true
  upper   = false
  special = false
}


resource "aws_lambda_layer_version" "layer_version" {
  lifecycle {
    create_before_destroy = true
  }

  depends_on = [data.aws_lambda_invocation.trigger_codebuild_job]

  layer_name          = "${var.lambda_layer_name}-${replace(var.aft_version, ".", "-")}"
  compatible_runtimes = ["python${var.lambda_layer_python_version}"]
  s3_bucket           = var.s3_bucket_name
  s3_key              = "layer.zip"
}


# Copyright Amazon.com, Inc. or its affiliates. All rights reserved.
# SPDX-License-Identifier: Apache-2.0
#
output "layer_version_arn" {
  value = aws_lambda_layer_version.layer_version.arn
}


# Copyright Amazon.com, Inc. or its affiliates. All rights reserved.
# SPDX-License-Identifier: Apache-2.0
#
variable "lambda_layer_name" {
  type = string
  validation {
    condition     = can(regex("^[a-zA-Z0-9\\-]+$", var.lambda_layer_name))
    error_message = "Layer name must contain only alphanumeric characters and hyphens."
  }
}

variable "aft_tf_aws_customizations_module_url_ssm_path" {
  type = string
}

variable "aft_tf_aws_customizations_module_git_ref_ssm_path" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "lambda_layer_codebuild_delay" {
  type = string
}

variable "lambda_layer_python_version" {
  type = string
}

variable "lambda_runtime_python_version" {
  type = string
}

variable "s3_bucket_name" {
  type = string
}

variable "aft_kms_key_arn" {
  type = string
}

variable "aft_vpc_id" {
  type    = string
  default = null
}

variable "aft_vpc_private_subnets" {
  type    = list(string)
  default = null
}

variable "aft_vpc_default_sg" {
  type    = list(string)
  default = null
}
variable "aft_version" {
  type = string
}

variable "builder_archive_path" {
  type = string
}

variable "builder_archive_hash" {
  type = string
}

variable "cloudwatch_log_group_retention" {
  type = string
}

variable "cloudwatch_log_group_enable_cmk_encryption" {
  type = bool
}

variable "aft_enable_vpc" {
  type = bool
}

variable "codebuild_compute_type" {
  type = string
}


# Copyright Amazon.com, Inc. or its affiliates. All rights reserved.
# SPDX-License-Identifier: Apache-2.0
#
terraform {
  required_version = ">= 1.2.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0.0, < 7.0.0"
    }
  }
}