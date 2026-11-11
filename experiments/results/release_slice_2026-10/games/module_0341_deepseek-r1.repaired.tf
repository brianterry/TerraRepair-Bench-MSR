data "aws_partition" "current" {}

data "aws_region" "current" {
  provider = aws.aft_management
}

data "aws_caller_identity" "current" {
  provider = aws.aft_management
}

data "aws_caller_identity" "ct_management" {
  provider = aws.ct_management
}

data "aws_caller_identity" "ct_audit" {
  provider = aws.audit
}

data "aws_caller_identity" "ct_log" {
  provider = aws.log_archive
}

data "aws_iam_policy" "AWSLambdaBasicExecutionRole" {
  provider = aws.aft_management
  name     = "AWSLambdaBasicExecutionRole"
}

data "aws_iam_policy" "AWSLambdaVPCAccessExecutionRole" {
  provider = aws.aft_management
  name     = "AWSLambdaVPCAccessExecutionRole"
}

data "aws_organizations_organization" "aft_organization" {
  provider = aws.ct_management
}

resource "aws_iam_role" "aft_features_sfn" {
  provider           = aws.aft_management
  name               = "aft-features-execution-role"
  assume_role_policy = templatefile("${path.module}/iam/trust-policies/states.tpl", { none = "none" })
}

resource "aws_iam_role_policy" "aft_features_sfn" {
  provider = aws.aft_management
  name     = "aft-features-policy"
  role     = aws_iam_role.aft_features_sfn.id

  policy = templatefile("${path.module}/iam/role-policies/aft_features_states.tpl", {
    data_aws_partition_current_partition               = data.aws_partition.current.partition
    data_aws_region_aft-management_name                = data.aws_region.current.region
    data_aws_caller_identity_aft-management_account_id = data.aws_caller_identity.current.id
    sns_topic_enable_cmk_encryption                    = var.sns_topic_enable_cmk_encryption
    aws_kms_key_aft_arn                                = var.aft_kms_key_arn
  })
}

resource "aws_iam_role" "aft_delete_default_vpc_lambda" {
  provider           = aws.aft_management
  name               = "aft-delete-default-vpc-execution-role"
  assume_role_policy = templatefile("${path.module}/iam/trust-policies/lambda.tpl", { none = "none" })
}

resource "aws_iam_role_policy" "aft_delete_default_vpc_lambda" {
  provider = aws.aft_management
  name     = "aft-delete-default-vpc-policy"
  role     = aws_iam_role.aft_delete_default_vpc_lambda.id

  policy = templatefile("${path.module}/iam/role-policies/aft_delete_default_vpc_lambda.tpl", {
    data_aws_caller_identity_current_account_id = data.aws_caller_identity.current.account_id
    data_aws_partition_current_partition        = data.aws_partition.current.partition
    data_aws_region_current_name                = data.aws_region.current.region
    aws_kms_key_aft_arn                         = var.aft_kms_key_arn
    aws_sns_topic_aft_notifications_arn         = var.aft_sns_topic_arn
    aws_sns_topic_aft_failure_notifications_arn = var.aft_failure_sns_topic_arn
  })
}

resource "aws_iam_role_policy_attachment" "aft_delete_default_vpc_lambda" {
  provider   = aws.aft_management
  count      = length(local.lambda_managed_policies)
  role       = aws_iam_role.aft_delete_default_vpc_lambda.name
  policy_arn = local.lambda_managed_policies[count.index]
}

resource "aws_iam_role" "aft_enroll_support" {
  provider           = aws.aft_management
  name               = "aft-enroll-support-execution-role"
  assume_role_policy = templatefile("${path.module}/iam/trust-policies/lambda.tpl", { none = "none" })
}

resource "aws_iam_role_policy" "aft_enroll_support" {
  provider = aws.aft_management
  name     = "aft-enroll-support-policy"
  role     = aws_iam_role.aft_enroll_support.id

  policy = templatefile("${path.module}/iam/role-policies/aft_enroll_support.tpl", {
    data_aws_caller_identity_current_account_id = data.aws_caller_identity.current.account_id
    data_aws_partition_current_partition        = data.aws_partition.current.partition
    data_aws_region_current_name                = data.aws_region.current.region
    aws_kms_key_aft_arn                         = var.aft_kms_key_arn
    aws_sns_topic_aft_notifications_arn         = var.aft_sns_topic_arn
    aws_sns_topic_aft_failure_notifications_arn = var.aft_failure_sns_topic_arn
  })
}

resource "aws_iam_role_policy_attachment" "aft_enroll_support" {
  provider   = aws.aft_management
  count      = length(local.lambda_managed_policies)
  role       = aws_iam_role.aft_enroll_support.name
  policy_arn = local.lambda_managed_policies[count.index]
}

resource "aws_iam_role" "aft_enable_cloudtrail" {
  provider           = aws.aft_management
  name               = "aft-enable-cloudtrail-execution-role"
  assume_role_policy = templatefile("${path.module}/iam/trust-policies/lambda.tpl", { none = "none" })
}

resource "aws_iam_role_policy" "aft_enable_cloudtrail" {
  provider = aws.aft_management
  name     = "aft-enable-cloudtrail-policy"
  role     = aws_iam_role.aft_enable_cloudtrail.id

  policy = templatefile("${path.module}/iam/role-policies/aft_enable_cloudtrail.tpl", {
    data_aws_caller_identity_current_account_id = data.aws_caller_identity.current.account_id
    data_aws_partition_current_partition        = data.aws_partition.current.partition
    data_aws_region_current_name                = data.aws_region.current.region
    aws_kms_key_aft_arn                         = var.aft_kms_key_arn
    aws_sns_topic_aft_notifications_arn         = var.aft_sns_topic_arn
    aws_sns_topic_aft_failure_notifications_arn = var.aft_failure_sns_topic_arn
  })
}

resource "aws_iam_role_policy_attachment" "aft_enable_cloudtrail" {
  provider   = aws.aft_management
  count      = length(local.lambda_managed_policies)
  role       = aws_iam_role.aft_enable_cloudtrail.name
  policy_arn = local.lambda_managed_policies[count.index]
}

resource "aws_kms_key" "aft_log_key" {
  provider            = aws.log_archive
  description         = "KMS key for encrypt/decrypt log files"
  enable_key_rotation = "true"
  policy = templatefile("${path.module}/kms/key-policies/log-key.tpl", {
    log_archive_account_id               = var.log_archive_account_id
    data_aws_partition_current_partition = data.aws_partition.current.partition
  })
}

resource "aws_kms_alias" "aft_log_key_alias" {
  provider = aws.log_archive

  name          = "alias/aft"
  target_key_id = aws_kms_key.aft_log_key.key_id
}

resource "aws_lambda_function" "aft_delete_default_vpc" {
  provider      = aws.aft_management
  filename      = var.feature_options_archive_path
  function_name = var.delete_default_vpc_lambda_function_name
  description   = "Deletes default VPCs in all regions. Called from aft-features SFN."
  role          = aws_iam_role.aft_delete_default_vpc_lambda.arn
  handler       = "aft_delete_default_vpc.lambda_handler"

  source_code_hash = var.feature_options_archive_hash
  memory_size      = 1024
  runtime          = var.lambda_runtime_python_version
  timeout          = "300"
  layers           = [var.aft_common_layer_arn]

  dead_letter_config {
    target_arn = var.aft_failure_sns_topic_arn
  }

  reserved_concurrent_executions = 1

  tracing_config {
    mode = "Active"
  }

  dynamic "vpc_config" {
    for_each = var.aft_enable_vpc ? [1] : []

    content {
      subnet_ids         = var.aft_vpc_private_subnets
      security_group_ids = var.aft_vpc_default_sg
    }
  }
}

resource "aws_cloudwatch_log_group" "aft_delete_default_vpc" {
  provider          = aws.aft_management
  name              = "/aws/lambda/${aws_lambda_function.aft_delete_default_vpc.function_name}"
  retention_in_days = var.cloudwatch_log_group_retention
  kms_key_id        = var.cloudwatch_log_group_enable_cmk_encryption ? var.aft_kms_key_arn : null
}

resource "aws_lambda_function" "aft_enroll_support" {
  provider      = aws.aft_management
  filename      = var.feature_options_archive_path
  function_name = var.enroll_support_lambda_function_name
  description   = "Creates request to enroll an account in Enterprise support. Called from aft-features SFN."
  role          = aws_iam_role.aft_enroll_support.arn
  handler       = "aft_enroll_support.lambda_handler"

  source_code_hash = var.feature_options_archive_hash
  memory_size      = 1024
  runtime          = var.lambda_runtime_python_version
  timeout          = "300"
  layers           = [var.aft_common_layer_arn]

  dead_letter_config {
    target_arn = var.aft_failure_sns_topic_arn
  }

  reserved_concurrent_executions = 1

  tracing_config {
    mode = "Active"
  }

  dynamic "vpc_config" {
    for_each = var.aft_enable_vpc ? [1] : []

    content {
      subnet_ids         = var.aft_vpc_private_subnets
      security_group_ids = var.aft_vpc_default_sg
    }
  }
}

resource "aws_cloudwatch_log_group" "aft_enroll_support" {
  provider          = aws.aft_management
  name              = "/aws/lambda/${aws_lambda_function.aft_enroll_support.function_name}"
  retention_in_days = var.cloudwatch_log_group_retention
  kms_key_id        = var.cloudwatch_log_group_enable_cmk_encryption ? var.aft_kms_key_arn : null
}

resource "aws_lambda_function" "aft_enable_cloudtrail" {
  provider      = aws.aft_management
  filename      = var.feature_options_archive_path
  function_name = var.enable_cloudtrail_lambda_function_name
  description   = "Creates an Org Trail to capture data events. Called from aft-features SFN."
  role          = aws_iam_role.aft_enable_cloudtrail.arn
  handler       = "aft_enable_cloudtrail.lambda_handler"

  source_code_hash = var.feature_options_archive_hash
  memory_size      = 1024
  runtime          = var.lambda_runtime_python_version
  timeout          = "300"
  layers           = [var.aft_common_layer_arn]

  dead_letter_config {
    target_arn = var.aft_failure_sns_topic_arn
  }

  reserved_concurrent_executions = 1

  tracing_config {
    mode = "Active"
  }

  dynamic "vpc_config" {
    for_each = var.aft_enable_vpc ? [1] : []

    content {
      subnet_ids         = var.aft_vpc_private_subnets
      security_group_ids = var.aft_vpc_default_sg
    }
  }
}

resource "aws_cloudwatch_log_group" "aft_enable_cloudtrail" {
  provider          = aws.aft_management
  name              = "/aws/lambda/${aws_lambda_function.aft_enable_cloudtrail.function_name}"
  retention_in_days = var.cloudwatch_log_group_retention
  kms_key_id        = var.cloudwatch_log_group_enable_cmk_encryption ? var.aft_kms_key_arn : null
}

locals {
  lambda_managed_policies = [data.aws_iam_policy.AWSLambdaBasicExecutionRole.arn, data.aws_iam_policy.AWSLambdaVPCAccessExecutionRole.arn]
}

output "aws_aft_access_logs_s3_bucket_id" {
  value       = aws_s3_bucket.aft_access_logs.id
  description = "The name of the bucket."
}

output "aws_aft_access_logs_s3_bucket_arn" {
  value       = aws_s3_bucket.aft_access_logs.arn
  description = "The ARN of the bucket. Will be of format arn:<partition>:s3:::bucketname."
}

output "aws_aft_access_logs_s3_bucket_region" {
  value       = aws_s3_bucket.aft_access_logs.region
  description = "The AWS region this bucket resides in."
}

output "aws_aft_logs_s3_bucket_id" {
  value       = aws_s3_bucket.aft_logging_bucket.id
  description = "The name of the bucket."
}

output "aws_aft_logs_s3_bucket_arn" {
  value       = aws_s3_bucket.aft_logging_bucket.arn
  description = "The ARN of the bucket. Will be of format arn:<partition>:s3:::bucketname."
}

output "aws_aft_logs_s3_bucket_region" {
  value       = aws_s3_bucket.aft_logging_bucket.region
  description = "The AWS region this bucket resides in."
}

output "aws_aft_log_key_arn" {
  value       = aws_kms_key.aft_log_key.arn
  description = "The ARN of the KMS key used to encrypt contents in the Log bucket"
}

output "state_machine_arn" {
  value       = aws_sfn_state_machine.aft_features.arn
  description = "The ARN of the Step Functions state machine"
}

resource "aws_s3_bucket" "aft_logging_bucket" {
  provider = aws.log_archive
  bucket   = "${var.log_archive_bucket_name}-${var.log_archive_account_id}-${data.aws_region.current.region}"
}

resource "aws_s3_bucket_logging" "aft_logging_bucket_logging" {
  provider      = aws.log_archive
  bucket        = aws_s3_bucket.aft_logging_bucket.id
  target_bucket = aws_s3_bucket.aft_access_logs.id
  target_prefix = "log/"
}

resource "aws_s3_bucket_versioning" "aft_logging_bucket_versioning" {
  provider = aws.log_archive
  bucket   = aws_s3_bucket.aft_logging_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "aft_logging_bucket_encryption" {
  provider = aws.log_archive
  bucket   = aws_s3_bucket.aft_logging_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.aft_log_key.arn
      sse_algorithm     = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "aft_logging_bucket_lifecycle_configuration" {
  provider = aws.log_archive
  bucket   = aws_s3_bucket.aft_logging_bucket.id
  rule {
    status = "Enabled"
    id     = "aft_logging_bucket_lifecycle_configuration_rule"

    filter {
      prefix = ""
    }

    noncurrent_version_expiration {
      noncurrent_days = var.log_archive_bucket_object_expiration_days
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

resource "aws_s3_bucket_policy" "aft_logging_bucket" {
  provider = aws.log_archive
  bucket   = aws_s3_bucket.aft_logging_bucket.id
  policy = templatefile("${path.module}/s3/bucket-policies/aft_logging_bucket.tpl", {
    aws_s3_bucket_aft_logging_bucket_arn                    = aws_s3_bucket.aft_logging_bucket.arn
    data_aws_organizations_organization_aft_organization_id = data.aws_organizations_organization.aft_organization.id
  })
}

resource "aws_s3_bucket_public_access_block" "aft_logging_bucket" {
  provider                = aws.log_archive
  bucket                  = aws_s3_bucket.aft_logging_bucket.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket" "aft_access_logs" {
  provider = aws.log_archive
  bucket   = "${var.log_archive_access_logs_bucket_name}-${var.log_archive_account_id}-${data.aws_region.current.region}"
}

resource "aws_s3_bucket_logging" "aft_access_logs_logging" {
  provider      = aws.log_archive
  bucket        = aws_s3_bucket.aft_access_logs.id
  target_bucket = aws_s3_bucket.aft_access_logs.id
  target_prefix = "logs/"
}

resource "aws_s3_bucket_policy" "aft_access_logs" {
  provider = aws.log_archive
  bucket   = aws_s3_bucket.aft_access_logs.id
  policy = templatefile("${path.module}/s3/bucket-policies/aft_access_logs.tpl", {
    aws_s3_bucket_aft_access_logs_arn    = aws_s3_bucket.aft_access_logs.arn
    aws_s3_bucket_aft_logging_bucket_arn = aws_s3_bucket.aft_logging_bucket.arn
    log_archive_account_id               = var.log_archive_account_id
  })
}

resource "aws_s3_bucket_versioning" "aft_access_logs_versioning" {
  provider = aws.log_archive
  bucket   = aws_s3_bucket.aft_access_logs.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "aft_access_logs_encryption" {
  provider = aws.log_archive
  bucket   = aws_s3_bucket.aft_access_logs.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.aft_log_key.arn
      sse_algorithm     = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "aft_access_logs_lifecycle_configuration" {
  provider = aws.log_archive
  bucket   = aws_s3_bucket.aft_access_logs.id
  rule {
    status = "Enabled"
    filter {
      prefix = "log/"
    }
    id = "aft_access_logs_lifecycle_configuration_rule"

    noncurrent_version_expiration {
      noncurrent_days = var.log_archive_bucket_object_expiration_days
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

resource "aws_s3_bucket_public_access_block" "aft_access_logs" {
  provider                = aws.log_archive
  bucket                  = aws_s3_bucket.aft_access_logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

locals {
  state_machine_source = "${path.module}/states/aft_features.asl.json"
  replacements_map = {
    current_partition                   = data.aws_partition.current.partition
    aft_delete_default_vpc_function_arn = aws_lambda_function.aft_delete_default_vpc.arn
    aft_enroll_support_function_arn     = aws_lambda_function.aft_enroll_support.arn
    aft_enable_cloudtrail_function_arn  = aws_lambda_function.aft_enable_cloudtrail.arn
    aft_notification_arn                = var.aft_sns_topic_arn
    aft_failure_notification_arn        = var.aft_failure_sns_topic_arn
  }
}

resource "aws_sfn_state_machine" "aft_features" {
  provider   = aws.aft_management
  name       = var.aft_features_sfn_name
  role_arn   = aws_iam_role.aft_features_sfn.arn
  definition = templatefile(local.state_machine_source, local.replacements_map)

  tracing_configuration {
    enabled = true
  }

  logging_configuration {
    log_destination        = "${aws_cloudwatch_log_group.aft_features.arn}:*"
    include_execution_data = true
    level                  = "ALL"
  }
}

resource "aws_cloudwatch_log_group" "aft_features" {
  provider          = aws.aft_management
  name              = "/aws/vendedlogs/states/${var.aft_features_sfn_name}"
  retention_in_days = var.cloudwatch_log_group_retention
  kms_key_id        = var.cloudwatch_log_group_enable_cmk_encryption ? var.aft_kms_key_arn : null
}

variable "aft_vpc_private_subnets" {
  type    = list(string)
  default = null
}

variable "aft_vpc_default_sg" {
  type    = list(string)
  default = null
}

variable "aft_common_layer_arn" {
  type = string
}

variable "cloudwatch_log_group_retention" {
  type = string
}

variable "cloudwatch_log_group_enable_cmk_encryption" {
  type = bool
}

variable "sns_topic_enable_cmk_encryption" {
  type = bool
}

variable "aft_kms_key_arn" {
  type = string
}

variable "aft_kms_key_id" {
  type = string
}

variable "aft_sns_topic_arn" {
  type = string
}

variable "aft_failure_sns_topic_arn" {
  type = string
}

variable "log_archive_bucket_name" {
  type = string
}

variable "log_archive_access_logs_bucket_name" {
  type = string
}

variable "log_archive_bucket_object_expiration_days" {
  type = number
}

variable "log_archive_account_id" {
  type = string
}

variable "aft_features_sfn_name" {
  type = string
}
variable "feature_options_archive_path" {
  type = string
}

variable "feature_options_archive_hash" {
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

terraform {
  required_version = ">= 1.2.0, < 2.0.0"

  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = ">= 4.27.0"
      configuration_aliases = [aws.ct_management, aws.log_archive, aws.audit, aws.aft_management]
    }
  }
}