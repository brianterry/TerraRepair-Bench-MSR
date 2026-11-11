# Copyright Amazon.com, Inc. or its affiliates. All rights reserved.
# SPDX-License-Identifier: Apache-2.0
#
resource "aws_backup_vault" "aft_controltower_backup_vault" {
  name        = "aft-controltower-backup-vault"
  kms_key_arn = aws_kms_key.aft.arn
}
resource "aws_backup_plan" "aft_controltower_backup_plan" {
  name = "aft-controltower-backup-plan"
  rule {
    rule_name         = "aft_controltower_backup_rule"
    target_vault_name = aws_backup_vault.aft_controltower_backup_vault.name
    schedule          = "cron(0 * * * ? *)"

    dynamic "lifecycle" {
      for_each = var.backup_recovery_point_retention != null ? [1] : []
      content {
        delete_after = var.backup_recovery_point_retention
      }
    }

  }
}

resource "aws_backup_selection" "aft_controltower_backup_selection" {
  iam_role_arn = aws_iam_role.aft_aws_backup.arn
  name         = "aft-controltower-backup-selection"
  plan_id      = aws_backup_plan.aft_controltower_backup_plan.id
  resources = [
    aws_dynamodb_table.aft_request_metadata.arn,
    aws_dynamodb_table.aft_request.arn,
    aws_dynamodb_table.aft_request_audit.arn,
    aws_dynamodb_table.aft_controltower_events.arn
  ]

  condition {}
  not_resources = []

}


# Copyright Amazon.com, Inc. or its affiliates. All rights reserved.
# SPDX-License-Identifier: Apache-2.0
#
data "aws_partition" "current" {}

data "aws_region" "aft-management" {}

data "aws_caller_identity" "aft-management" {}

data "aws_caller_identity" "ct-management" {
  provider = aws.ct_management
}

data "aws_iam_policy" "AWSLambdaBasicExecutionRole" {
  name = "AWSLambdaBasicExecutionRole"
}

data "aws_iam_policy" "AWSLambdaVPCAccessExecutionRole" {
  name = "AWSLambdaVPCAccessExecutionRole"
}

data "aws_availability_zones" "available" {
  state = "available"
  filter {
    name   = "zone-id"
    values = ["*"]
  }
}

data "aws_vpc" "aft" {
  count = local.vpc_deployment ? 1 : 0

  id = local.vpc_id
}

data "aws_route_tables" "aft_private_route_tables" {
  count = local.vpc_deployment && var.aft_vpc_endpoints ? 1 : 0

  vpc_id = local.vpc_id

  filter {
    name   = "association.subnet-id"
    values = local.vpc_private_subnet_ids
  }
}

data "aws_route_tables" "aft_public_route_tables" {
  count = local.vpc_deployment && var.aft_vpc_endpoints ? 1 : 0

  vpc_id = local.vpc_id

  filter {
    name   = "association.subnet-id"
    values = local.vpc_public_subnet_ids
  }
}

data "aws_vpc_endpoint_service" "codebuild" {
  count   = local.vpc_deployment && var.aft_vpc_endpoints ? 1 : 0
  service = "codebuild"
}

data "aws_subnets" "codebuild" {
  count = local.vpc_deployment && var.aft_vpc_endpoints ? 1 : 0

  filter {
    name   = "vpc-id"
    values = [local.vpc_id]
  }

  filter {
    name   = "subnet-id"
    values = local.vpc_private_subnet_ids
  }

  filter {
    name   = "availability-zone"
    values = data.aws_vpc_endpoint_service.codebuild[0].availability_zones
  }
}

data "aws_vpc_endpoint_service" "codecommit" {
  count   = local.vpc_deployment && var.aft_vpc_endpoints ? 1 : 0
  service = "codecommit"
}

data "aws_subnets" "codecommit" {
  count = local.vpc_deployment && var.aft_vpc_endpoints ? 1 : 0
  filter {
    name   = "vpc-id"
    values = [local.vpc_id]
  }

  filter {
    name   = "subnet-id"
    values = local.vpc_private_subnet_ids
  }

  filter {
    name   = "availability-zone"
    values = data.aws_vpc_endpoint_service.codecommit[0].availability_zones
  }
}

data "aws_vpc_endpoint_service" "git-codecommit" {
  count   = local.vpc_deployment && var.aft_vpc_endpoints ? 1 : 0
  service = "git-codecommit"
}

data "aws_subnets" "git-codecommit" {

  count = local.vpc_deployment && var.aft_vpc_endpoints ? 1 : 0
  filter {
    name   = "vpc-id"
    values = [local.vpc_id]
  }

  filter {
    name   = "subnet-id"
    values = local.vpc_private_subnet_ids
  }

  filter {
    name   = "availability-zone"
    values = data.aws_vpc_endpoint_service.git-codecommit[0].availability_zones
  }
}

data "aws_vpc_endpoint_service" "codepipeline" {
  count   = local.vpc_deployment && var.aft_vpc_endpoints ? 1 : 0
  service = "codepipeline"
}

data "aws_subnets" "codepipeline" {
  count = local.vpc_deployment && var.aft_vpc_endpoints ? 1 : 0

  filter {
    name   = "vpc-id"
    values = [local.vpc_id]
  }

  filter {
    name   = "subnet-id"
    values = local.vpc_private_subnet_ids
  }

  filter {
    name   = "availability-zone"
    values = data.aws_vpc_endpoint_service.codepipeline[0].availability_zones
  }
}

data "aws_vpc_endpoint_service" "servicecatalog" {
  count   = local.vpc_deployment && var.aft_vpc_endpoints ? 1 : 0
  service = "servicecatalog"
}

data "aws_subnets" "servicecatalog" {
  count = local.vpc_deployment && var.aft_vpc_endpoints ? 1 : 0
  filter {
    name   = "vpc-id"
    values = [local.vpc_id]
  }

  filter {
    name   = "subnet-id"
    values = local.vpc_private_subnet_ids
  }

  filter {
    name   = "availability-zone"
    values = data.aws_vpc_endpoint_service.servicecatalog[0].availability_zones
  }
}

data "aws_vpc_endpoint_service" "lambda" {
  count   = local.vpc_deployment && var.aft_vpc_endpoints ? 1 : 0
  service = "lambda"
}

data "aws_subnets" "lambda" {
  count = local.vpc_deployment && var.aft_vpc_endpoints ? 1 : 0
  filter {
    name   = "vpc-id"
    values = [local.vpc_id]
  }
  filter {
    name   = "subnet-id"
    values = local.vpc_private_subnet_ids
  }

  filter {
    name   = "availability-zone"
    values = data.aws_vpc_endpoint_service.lambda[0].availability_zones
  }
}

data "aws_vpc_endpoint_service" "kms" {
  count   = local.vpc_deployment && var.aft_vpc_endpoints ? 1 : 0
  service = "kms"
}

data "aws_subnets" "kms" {
  count = local.vpc_deployment && var.aft_vpc_endpoints ? 1 : 0
  filter {
    name   = "vpc-id"
    values = [local.vpc_id]
  }

  filter {
    name   = "subnet-id"
    values = local.vpc_private_subnet_ids
  }

  filter {
    name   = "availability-zone"
    values = data.aws_vpc_endpoint_service.kms[0].availability_zones
  }
}

data "aws_vpc_endpoint_service" "logs" {
  count   = local.vpc_deployment && var.aft_vpc_endpoints ? 1 : 0
  service = "logs"
}

data "aws_subnets" "logs" {

  count = local.vpc_deployment && var.aft_vpc_endpoints ? 1 : 0
  filter {
    name   = "vpc-id"
    values = [local.vpc_id]
  }
  filter {
    name   = "subnet-id"
    values = local.vpc_private_subnet_ids
  }

  filter {
    name   = "availability-zone"
    values = data.aws_vpc_endpoint_service.logs[0].availability_zones
  }
}

data "aws_vpc_endpoint_service" "events" {
  count   = local.vpc_deployment && var.aft_vpc_endpoints ? 1 : 0
  service = "events"
}

data "aws_subnets" "events" {
  count = local.vpc_deployment && var.aft_vpc_endpoints ? 1 : 0
  filter {
    name   = "vpc-id"
    values = [local.vpc_id]
  }

  filter {
    name   = "subnet-id"
    values = local.vpc_private_subnet_ids
  }

  filter {
    name   = "availability-zone"
    values = data.aws_vpc_endpoint_service.events[0].availability_zones
  }
}

data "aws_vpc_endpoint_service" "organizations" {
  count   = local.vpc_deployment && var.aft_vpc_endpoints && local.orgs_endpoint_supported ? 1 : 0
  service = "organizations"
}

data "aws_subnets" "organizations" {
  count = local.vpc_deployment && var.aft_vpc_endpoints && local.orgs_endpoint_supported ? 1 : 0

  filter {
    name   = "vpc-id"
    values = [local.vpc_id]
  }

  filter {
    name   = "subnet-id"
    values = local.vpc_private_subnet_ids
  }

  filter {
    name   = "availability-zone"
    values = data.aws_vpc_endpoint_service.organizations[0].availability_zones
  }
}

data "aws_vpc_endpoint_service" "states" {
  count   = local.vpc_deployment && var.aft_vpc_endpoints ? 1 : 0
  service = "states"
}

data "aws_subnets" "states" {
  count = local.vpc_deployment && var.aft_vpc_endpoints ? 1 : 0
  filter {
    name   = "vpc-id"
    values = [local.vpc_id]
  }
  filter {
    name   = "subnet-id"
    values = local.vpc_private_subnet_ids
  }

  filter {
    name   = "availability-zone"
    values = data.aws_vpc_endpoint_service.states[0].availability_zones
  }
}

data "aws_vpc_endpoint_service" "ssm" {
  count   = local.vpc_deployment && var.aft_vpc_endpoints ? 1 : 0
  service = "ssm"
}

data "aws_subnets" "ssm" {

  count = local.vpc_deployment && var.aft_vpc_endpoints ? 1 : 0
  filter {
    name   = "vpc-id"
    values = [local.vpc_id]
  }

  filter {
    name   = "subnet-id"
    values = local.vpc_private_subnet_ids
  }

  filter {
    name   = "availability-zone"
    values = data.aws_vpc_endpoint_service.ssm[0].availability_zones
  }
}

data "aws_vpc_endpoint_service" "sns" {
  count   = local.vpc_deployment && var.aft_vpc_endpoints ? 1 : 0
  service = "sns"
}

data "aws_subnets" "sns" {
  count = local.vpc_deployment && var.aft_vpc_endpoints ? 1 : 0
  filter {
    name   = "vpc-id"
    values = [local.vpc_id]
  }

  filter {
    name   = "subnet-id"
    values = local.vpc_private_subnet_ids
  }

  filter {
    name   = "availability-zone"
    values = data.aws_vpc_endpoint_service.sns[0].availability_zones
  }
}

data "aws_vpc_endpoint_service" "sqs" {
  count   = local.vpc_deployment && var.aft_vpc_endpoints ? 1 : 0
  service = "sqs"
}

data "aws_subnets" "sqs" {
  count = local.vpc_deployment && var.aft_vpc_endpoints ? 1 : 0
  filter {
    name   = "vpc-id"
    values = [local.vpc_id]
  }

  filter {
    name   = "subnet-id"
    values = local.vpc_private_subnet_ids
  }

  filter {
    name   = "availability-zone"
    values = data.aws_vpc_endpoint_service.sqs[0].availability_zones
  }
}

data "aws_vpc_endpoint_service" "sts" {
  count   = local.vpc_deployment && var.aft_vpc_endpoints ? 1 : 0
  service = "sts"
}

data "aws_subnets" "sts" {
  count = local.vpc_deployment && var.aft_vpc_endpoints ? 1 : 0
  filter {
    name   = "vpc-id"
    values = [local.vpc_id]
  }

  filter {
    name   = "subnet-id"
    values = local.vpc_private_subnet_ids
  }

  filter {
    name   = "availability-zone"
    values = data.aws_vpc_endpoint_service.sts[0].availability_zones
  }
}


# Copyright Amazon.com, Inc. or its affiliates. All rights reserved.
# SPDX-License-Identifier: Apache-2.0
#
resource "aws_dynamodb_table" "aft_request_metadata" {
  name         = "aft-request-metadata"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }

  attribute {
    name = "email"
    type = "S"
  }

  attribute {
    name = "type"
    type = "S"
  }

  global_secondary_index {
    name            = "typeIndex"
    hash_key        = "type"
    projection_type = "ALL"
  }

  global_secondary_index {
    name               = "emailIndex"
    hash_key           = "email"
    projection_type    = "INCLUDE"
    non_key_attributes = ["id"]
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.aft.arn
  }
}

resource "aws_dynamodb_table" "aft_request" {
  name             = "aft-request"
  billing_mode     = "PAY_PER_REQUEST"
  hash_key         = "id"
  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"

  attribute {
    name = "id"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.aft.arn
  }
}

resource "aws_dynamodb_table" "aft_request_audit" {
  name             = "aft-request-audit"
  billing_mode     = "PAY_PER_REQUEST"
  hash_key         = "id"
  range_key        = "timestamp"
  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"

  attribute {
    name = "id"
    type = "S"
  }

  attribute {
    name = "timestamp"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.aft.arn
  }
}

resource "aws_dynamodb_table" "aft_controltower_events" {
  name             = "aft-controltower-events"
  billing_mode     = "PAY_PER_REQUEST"
  hash_key         = "id"
  range_key        = "time"
  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"

  attribute {
    name = "id"
    type = "S"
  }

  attribute {
    name = "time"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.aft.arn
  }
}


# Copyright Amazon.com, Inc. or its affiliates. All rights reserved.
# SPDX-License-Identifier: Apache-2.0
#
resource "aws_cloudwatch_event_bus" "aft_from_ct_management" {
  name = "aft-events-from-ct-management"
}

resource "aws_cloudwatch_event_permission" "control_tower_management_account" {
  principal      = data.aws_caller_identity.ct-management.account_id
  statement_id   = "control_tower_management_account"
  event_bus_name = aws_cloudwatch_event_bus.aft_from_ct_management.name
}

resource "aws_cloudwatch_event_rule" "aft_control_tower_events" {
  provider      = aws.ct_management
  name          = "aft-capture-ct-events"
  description   = "Capture ControlTower events"
  event_pattern = <<EOF
{
  "source": ["aws.controltower"],
  "detail-type": ["AWS Service Event via CloudTrail"],
  "detail": {
    "eventName": ["CreateManagedAccount", "UpdateManagedAccount"]
  }
}
EOF
}

resource "aws_cloudwatch_event_target" "aft_management_event_bus" {
  provider = aws.ct_management
  arn      = aws_cloudwatch_event_bus.aft_from_ct_management.arn
  rule     = aws_cloudwatch_event_rule.aft_control_tower_events.id
  role_arn = aws_iam_role.aft_control_tower_events.arn
}

resource "aws_cloudwatch_event_rule" "aft_controltower_event_trigger" {
  name           = "aft-controltower-event-logger"
  description    = "Send CT Events to Lambda"
  event_bus_name = aws_cloudwatch_event_bus.aft_from_ct_management.name
  event_pattern  = <<EOF
{
  "account": ["${data.aws_caller_identity.ct-management.account_id}"]
}
EOF
}

resource "aws_cloudwatch_event_target" "aft_controltower_event_logger" {
  rule           = aws_cloudwatch_event_rule.aft_controltower_event_trigger.name
  arn            = aws_lambda_function.aft_controltower_event_logger.arn
  event_bus_name = aws_cloudwatch_event_bus.aft_from_ct_management.name
}

resource "aws_cloudwatch_event_target" "aft_invoke_aft_account_provisioning_framework" {
  rule           = aws_cloudwatch_event_rule.aft_controltower_event_trigger.name
  arn            = aws_lambda_function.aft_invoke_aft_account_provisioning_framework.arn
  event_bus_name = aws_cloudwatch_event_bus.aft_from_ct_management.name
}

resource "aws_cloudwatch_event_rule" "aft_account_request_processor" {
  name                = "aft-lambda-account-request-processor"
  description         = "Trigger Lambda"
  schedule_expression = "rate(5 minutes)"
}

resource "aws_cloudwatch_event_target" "aft_account_request_processor" {
  arn  = aws_lambda_function.aft_account_request_processor.arn
  rule = aws_cloudwatch_event_rule.aft_account_request_processor.id
}


# Copyright Amazon.com, Inc. or its affiliates. All rights reserved.
# SPDX-License-Identifier: Apache-2.0
#
resource "aws_iam_role" "aft_control_tower_events" {
  provider           = aws.ct_management
  name               = "aft-control-tower-events-rule"
  assume_role_policy = templatefile("${path.module}/iam/trust-policies/events.tpl", { none = "none" })
}

resource "aws_iam_role_policy" "control_tower_events" {
  provider = aws.ct_management
  name     = "control-tower-events"
  role     = aws_iam_role.aft_control_tower_events.id

  policy = templatefile("${path.module}/iam/role-policies/events-control-tower-events.tpl", {
    aws_cloudwatch_event_bus_from-ct-management_arn = aws_cloudwatch_event_bus.aft_from_ct_management.arn
  })
}

resource "aws_iam_role" "aft_account_request_audit_trigger" {
  name               = "aft-lambda-account-request-audit-trigger"
  assume_role_policy = templatefile("${path.module}/iam/trust-policies/lambda.tpl", { none = "none" })
}

resource "aws_iam_role_policy_attachment" "aft_account_request_audit_trigger" {
  count      = length(local.lambda_managed_policies)
  role       = aws_iam_role.aft_account_request_audit_trigger.name
  policy_arn = local.lambda_managed_policies[count.index]
}

resource "aws_iam_role_policy" "aft_account_request_audit_trigger" {
  name = "aft-account-request-audit-trigger"
  role = aws_iam_role.aft_account_request_audit_trigger.id

  policy = templatefile("${path.module}/iam/role-policies/lambda-account-request-audit-trigger.tpl", {
    data_aws_partition_current_partition               = data.aws_partition.current.partition
    data_aws_region_aft-management_name                = data.aws_region.aft-management.region
    data_aws_caller_identity_aft-management_account_id = data.aws_caller_identity.aft-management.account_id
    aws_sns_topic_aft_notifications_arn                = aws_sns_topic.aft_notifications.arn
    aws_sns_topic_aft_failure_notifications_arn        = aws_sns_topic.aft_failure_notifications.arn
    aws_dynamodb_table_aft-request_name                = aws_dynamodb_table.aft_request.name
    aws_dynamodb_table_aft-request-audit_name          = aws_dynamodb_table.aft_request_audit.name
    aws_sqs_queue_aft_account_request_arn              = aws_sqs_queue.aft_account_request.arn
    aws_kms_key_aft_arn                                = aws_kms_key.aft.arn
  })
}

resource "aws_iam_role" "aft_account_request_action_trigger" {
  name               = "aft-lambda-account-request-action-trigger"
  assume_role_policy = templatefile("${path.module}/iam/trust-policies/lambda.tpl", { none = "none" })
}

resource "aws_iam_role_policy_attachment" "aft_account_request_action_trigger" {
  count      = length(local.lambda_managed_policies)
  role       = aws_iam_role.aft_account_request_action_trigger.name
  policy_arn = local.lambda_managed_policies[count.index]
}

resource "aws_iam_role_policy" "aft_account_request_action_trigger" {
  name = "aft-account-request-action-trigger"
  role = aws_iam_role.aft_account_request_action_trigger.id

  policy = templatefile("${path.module}/iam/role-policies/lambda-account-request-action-trigger.tpl", {
    data_aws_partition_current_partition                              = data.aws_partition.current.partition
    data_aws_region_aft-management_name                               = data.aws_region.aft-management.region
    data_aws_caller_identity_aft-management_account_id                = data.aws_caller_identity.aft-management.account_id
    aws_sns_topic_aft_notifications_arn                               = aws_sns_topic.aft_notifications.arn
    aws_sns_topic_aft_failure_notifications_arn                       = aws_sns_topic.aft_failure_notifications.arn
    aws_lambda_function_invoke_aft_account_provisioning_framework_arn = aws_lambda_function.aft_invoke_aft_account_provisioning_framework.arn
    aws_lambda_function_cleanup_resources_arn                         = aws_lambda_function.aft_cleanup_resources.arn
    aws_sqs_queue_aft_account_request_arn                             = aws_sqs_queue.aft_account_request.arn
    aws_kms_key_aft_arn                                               = aws_kms_key.aft.arn
    aws_dynamodb_table_aft-request_name                               = aws_dynamodb_table.aft_request.name
    aws_dynamodb_table_aft-request-audit_name                         = aws_dynamodb_table.aft_request_audit.name
  })
}

resource "aws_iam_role" "aft_controltower_event_logger" {
  name               = "aft-lambda-controltower-event-logger"
  assume_role_policy = templatefile("${path.module}/iam/trust-policies/lambda.tpl", { none = "none" })
}

resource "aws_iam_role_policy_attachment" "aft_controltower_event_logger" {
  count      = length(local.lambda_managed_policies)
  role       = aws_iam_role.aft_controltower_event_logger.name
  policy_arn = local.lambda_managed_policies[count.index]
}

resource "aws_iam_role_policy" "aft_controltower_event_logger" {
  name = "aft-controltower-event-logger"
  role = aws_iam_role.aft_controltower_event_logger.id

  policy = templatefile("${path.module}/iam/role-policies/lambda-controltower-event-logger.tpl", {
    data_aws_partition_current_partition               = data.aws_partition.current.partition
    data_aws_region_aft-management_name                = data.aws_region.aft-management.region
    data_aws_caller_identity_aft-management_account_id = data.aws_caller_identity.aft-management.account_id
    aws_dynamodb_table_controltower-events_name        = aws_dynamodb_table.aft_controltower_events.name
    aws_sns_topic_aft_notifications_arn                = aws_sns_topic.aft_notifications.arn
    aws_sns_topic_aft_failure_notifications_arn        = aws_sns_topic.aft_failure_notifications.arn
    aws_kms_key_aft_arn                                = aws_kms_key.aft.arn
  })
}

resource "aws_iam_role" "aft_account_request_processor" {
  name               = "aft-lambda-account-request-processor"
  assume_role_policy = templatefile("${path.module}/iam/trust-policies/lambda.tpl", { none = "none" })
}

resource "aws_iam_role_policy_attachment" "account_request_processor" {
  count      = length(local.lambda_managed_policies)
  role       = aws_iam_role.aft_account_request_processor.name
  policy_arn = local.lambda_managed_policies[count.index]
}

resource "aws_iam_role_policy" "aft_account_request_processor" {
  name = "aft-account-request-processor"
  role = aws_iam_role.aft_account_request_processor.id

  policy = templatefile("${path.module}/iam/role-policies/lambda-account-request-processor.tpl", {
    data_aws_partition_current_partition               = data.aws_partition.current.partition
    data_aws_region_aft-management_name                = data.aws_region.aft-management.region
    data_aws_caller_identity_aft-management_account_id = data.aws_caller_identity.aft-management.account_id
    aws_kms_key_aft_arn                                = aws_kms_key.aft.arn
    aws_sns_topic_aft_notifications_arn                = aws_sns_topic.aft_notifications.arn
    aws_sns_topic_aft_failure_notifications_arn        = aws_sns_topic.aft_failure_notifications.arn
    aws_sqs_queue_aft_account_request_arn              = aws_sqs_queue.aft_account_request.arn
  })
}


resource "aws_iam_role" "aft_invoke_aft_account_provisioning_framework" {
  name               = "aft-lambda-invoke-aft-account-provisioning-framework"
  assume_role_policy = templatefile("${path.module}/iam/trust-policies/lambda.tpl", { none = "none" })
}

resource "aws_iam_role_policy_attachment" "aft_invoke_aft_account_provisioning_framework" {
  count      = length(local.lambda_managed_policies)
  role       = aws_iam_role.aft_invoke_aft_account_provisioning_framework.name
  policy_arn = local.lambda_managed_policies[count.index]
}

resource "aws_iam_role_policy" "aft_invoke_aft_account_provisioning_framework" {
  name = "aft-invoke-account-provisioning-framework"
  role = aws_iam_role.aft_invoke_aft_account_provisioning_framework.id

  policy = templatefile("${path.module}/iam/role-policies/lambda-invoke-aft-account-provisioning-framework.tpl", {
    data_aws_partition_current_partition               = data.aws_partition.current.partition
    data_aws_region_aft-management_name                = data.aws_region.aft-management.region
    data_aws_caller_identity_aft-management_account_id = data.aws_caller_identity.aft-management.account_id
    aws_sns_topic_aft_notifications_arn                = aws_sns_topic.aft_notifications.arn
    aws_sns_topic_aft_failure_notifications_arn        = aws_sns_topic.aft_failure_notifications.arn
    aws_dynamodb_table_aft-request_name                = aws_dynamodb_table.aft_request.name
    var_aft_account_provisioning_framework_sfn_name    = var.aft_account_provisioning_framework_sfn_name
    aws_kms_key_aft_arn                                = aws_kms_key.aft.arn
  })
}

resource "aws_iam_role" "aft_cleanup_resources" {
  name               = "aft-lambda-cleanup-resources"
  assume_role_policy = templatefile("${path.module}/iam/trust-policies/lambda.tpl", { none = "none" })
}

resource "aws_iam_role_policy_attachment" "aft_cleanup_resources" {
  count      = length(local.lambda_managed_policies)
  role       = aws_iam_role.aft_cleanup_resources.name
  policy_arn = local.lambda_managed_policies[count.index]
}

resource "aws_iam_role_policy" "aft_cleanup_resources" {
  name = "aft-cleanup-resources"
  role = aws_iam_role.aft_cleanup_resources.id

  policy = templatefile("${path.module}/iam/role-policies/lambda-aft-cleanup-resources.tpl", {
    data_aws_partition_current_partition               = data.aws_partition.current.partition
    data_aws_region_aft-management_name                = data.aws_region.aft-management.region
    data_aws_caller_identity_aft-management_account_id = data.aws_caller_identity.aft-management.account_id
    aws_sns_topic_aft_notifications_arn                = aws_sns_topic.aft_notifications.arn
    aws_sns_topic_aft_failure_notifications_arn        = aws_sns_topic.aft_failure_notifications.arn
    aws_dynamodb_table_aft-request-metadata_name       = aws_dynamodb_table.aft_request_metadata.name
    aws_kms_key_aft_arn                                = aws_kms_key.aft.arn
  })
}

resource "aws_iam_role" "aft_aws_backup" {
  name               = "aft-aws-backup"
  assume_role_policy = templatefile("${path.module}/iam/trust-policies/backup.tpl", { none = "none" })
}
resource "aws_iam_role_policy_attachment" "aft_aws_backup_service_role" {
  role       = aws_iam_role.aft_aws_backup.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
}


# Copyright Amazon.com, Inc. or its affiliates. All rights reserved.
# SPDX-License-Identifier: Apache-2.0
#
resource "aws_kms_key" "aft" {
  description         = "AFT KMS key"
  enable_key_rotation = "true"
  policy = jsonencode(
    {
      "Version" : "2012-10-17",
      "Id" : "key-default-1",
      "Statement" : concat([
        {
          "Sid" : "Enable IAM User Permissions",
          "Effect" : "Allow",
          "Principal" : {
            "AWS" : "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.aft-management.account_id}:root"
          },
          "Action" : "kms:*",
          "Resource" : "*"
          }], var.cloudwatch_log_group_enable_cmk_encryption ? [{
          "Sid" : "Allow CloudWatch Logs access",
          "Effect" : "Allow",
          "Principal" : {
            "Service" : "logs.${data.aws_region.aft-management.region}.amazonaws.com"
          },
          "Action" : [
            "kms:Encrypt",
            "kms:Decrypt",
            "kms:ReEncrypt*",
            "kms:GenerateDataKey*",
            "kms:Describe*"
          ],
          "Resource" : "*",
          "Condition" : {
            "ArnEquals" : {
              "kms:EncryptionContext:aws:logs:arn" : "arn:${data.aws_partition.current.partition}:logs:${data.aws_region.aft-management.region}:${data.aws_caller_identity.aft-management.account_id}:*"
            }
          }
      }] : [])
  })
}


resource "aws_kms_alias" "aft" {
  name          = "alias/aft"
  target_key_id = aws_kms_key.aft.key_id
}


# Copyright Amazon.com, Inc. or its affiliates. All rights reserved.
# SPDX-License-Identifier: Apache-2.0
#

resource "aws_sqs_queue" "aft_account_request_audit_trigger_dlq" {
  name                              = "aft-account-request-audit-trigger-dlq"
  kms_master_key_id                 = aws_kms_alias.aft.name
  kms_data_key_reuse_period_seconds = 300
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

  dead_letter_config {
    target_arn = aws_sqs_queue.aft_account_request_audit_trigger_dlq.arn
  }

  code_signing_config_arn = aws_lambda_code_signing_config.aft_account_request_audit_trigger.arn

  tracing_config {
    mode = "Active"
  }

  dynamic "vpc_config" {
    for_each = local.vpc_deployment ? [1] : []

    content {
      subnet_ids         = local.vpc_private_subnet_ids
      security_group_ids = tolist([aws_security_group.aft_vpc_default_sg[0].id])
    }
  }

}

resource "aws_signer_signing_profile" "aft_account_request_audit_trigger" {
  platform_id = "AWSLambda-SHA384-ECDSA"
}

resource "aws_lambda_code_signing_config" "aft_account_request_audit_trigger" {
  allowed_publishers {
    signing_profile_version_arns = [aws_signer_signing_profile.aft_account_request_audit_trigger.version_arn]
  }

  policies {
    untrusted_artifact_on_deployment = "Enforce"
  }
}

resource "time_sleep" "wait_60_seconds" {
  depends_on      = [aws_dynamodb_table.aft_request, aws_lambda_function.aft_account_request_audit_trigger]
  create_duration = "60s"
}

resource "aws_lambda_event_source_mapping" "aft_account_request_audit_trigger" {
  depends_on             = [time_sleep.wait_60_seconds]
  event_source_arn       = aws_dynamodb_table.aft_request.stream_arn
  function_name          = aws_lambda_function.aft_account_request_audit_trigger.arn
  starting_position      = "LATEST"
  batch_size             = 1
  maximum_retry_attempts = 1
}

resource "aws_cloudwatch_log_group" "aft_account_request_audit_trigger" {
  name              = "/aws/lambda/${aws_lambda_function.aft_account_request_audit_trigger.function_name}"
  retention_in_days = var.cloudwatch_log_group_retention
  kms_key_id        = var.cloudwatch_log_group_enable_cmk_encryption ? aws_kms_key.aft.arn : null
}

resource "aws_sqs_queue" "aft_account_request_action_trigger_dlq" {
  name                              = "aft-account-request-action-trigger-dlq"
  kms_master_key_id                 = aws_kms_alias.aft.name
  kms_data_key_reuse_period_seconds = 300
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

  dead_letter_config {
    target_arn = aws_sqs_queue.aft_account_request_action_trigger_dlq.arn
  }

  code_signing_config_arn = aws_lambda_code_signing_config.aft_account_request_action_trigger.arn

  tracing_config {
    mode = "Active"
  }

  dynamic "vpc_config" {
    for_each = local.vpc_deployment ? [1] : []

    content {
      subnet_ids         = local.vpc_private_subnet_ids
      security_group_ids = tolist([aws_security_group.aft_vpc_default_sg[0].id])
    }
  }

}

resource "aws_signer_signing_profile" "aft_account_request_action_trigger" {
  platform_id = "AWSLambda-SHA384-ECDSA"
}

resource "aws_lambda_code_signing_config" "aft_account_request_action_trigger" {
  allowed_publishers {
    signing_profile_version_arns = [aws_signer_signing_profile.aft_account_request_action_trigger.version_arn]
  }

  policies {
    untrusted_artifact_on_deployment = "Enforce"
  }
}

resource "aws_lambda_event_source_mapping" "aft_account_request_action_trigger" {
  event_source_arn       = aws_dynamodb_table.aft_request.stream_arn
  function_name          = aws_lambda_function.aft_account_request_action_trigger.arn
  starting_position      = "LATEST"
  batch_size             = 1
  maximum_retry_attempts = 1
}

resource "aws_cloudwatch_log_group" "aft_account_request_action_trigger" {
  name              = "/aws/lambda/${aws_lambda_function.aft_account_request_action_trigger.function_name}"
  retention_in_days = var.cloudwatch_log_group_retention
  kms_key_id        = var.cloudwatch_log_group_enable_cmk_encryption ? aws_kms_key.aft.arn : null
}

resource "aws_sqs_queue" "aft_controltower_event_logger_dlq" {
  name                              = "aft-controltower-event-logger-dlq"
  kms_master_key_id                 = aws_kms_alias.aft.name
  kms_data_key_reuse_period_seconds = 300
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

  dead_letter_config {
    target_arn = aws_sqs_queue.aft_controltower_event_logger_dlq.arn
  }

  code_signing_config_arn = aws_lambda_code_signing_config.aft_controltower_event_logger.arn

  tracing_config {
    mode = "Active"
  }

  dynamic "vpc_config" {
    for_each = local.vpc_deployment ? [1] : []

    content {
      subnet_ids         = local.vpc_private_subnet_ids
      security_group_ids = tolist([aws_security_group.aft_vpc_default_sg[0].id])
    }
  }

}

resource "aws_signer_signing_profile" "aft_controltower_event_logger" {
  platform_id = "AWSLambda-SHA384-ECDSA"
}

resource "aws_lambda_code_signing_config" "aft_controltower_event_logger" {
  allowed_publishers {
    signing_profile_version_arns = [aws_signer_signing_profile.aft_controltower_event_logger.version_arn]
  }

  policies {
    untrusted_artifact_on_deployment = "Enforce"
  }
}

resource "aws_lambda_permission" "aft_controltower_event_logger" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.aft_controltower_event_logger.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.aft_controltower_event_trigger.arn
}

resource "aws_cloudwatch_log_group" "aft_controltower_event_logger" {
  name              = "/aws/lambda/${aws_lambda_function.aft_controltower_event_logger.function_name}"
  retention_in_days = var.cloudwatch_log_group_retention
  kms_key_id        = var.cloudwatch_log_group_enable_cmk_encryption ? aws_kms_key.aft.arn : null
}

resource "aws_sqs_queue" "aft_account_request_processor_dlq" {
  name                              = "aft-account-request-processor-dlq"
  kms_master_key_id                 = aws_kms_alias.aft.name
  kms_data_key_reuse_period_seconds = 300
}

resource "aws_kms_key" "aft_account_request_processor_env" {
  description         = "AFT Account Request Processor Lambda Environment Encryption Key"
  enable_key_rotation = true
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

  dead_letter_config {
    target_arn = aws_sqs_queue.aft_account_request_processor_dlq.arn
  }

  code_signing_config_arn = aws_lambda_code_signing_config.aft_account_request_processor.arn

  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      AFT_PROVISIONING_CONCURRENCY = var.concurrent_account_factory_actions
    }
  }

  kms_key_arn = aws_kms_key.aft_account_request_processor_env.arn

  dynamic "vpc_config" {
    for_each = local.vpc_deployment ? [1] : []

    content {
      subnet_ids         = local.vpc_private_subnet_ids
      security_group_ids = tolist([aws_security_group.aft_vpc_default_sg[0].id])
    }
  }

}

resource "aws_signer_signing_profile" "aft_account_request_processor" {
  platform_id = "AWSLambda-SHA384-ECDSA"
}

resource "aws_lambda_code_signing_config" "aft_account_request_processor" {
  allowed_publishers {
    signing_profile_version_arns = [aws_signer_signing_profile.aft_account_request_processor.version_arn]
  }

  policies {
    untrusted_artifact_on_deployment = "Enforce"
  }
}

resource "aws_lambda_permission" "aft_account_request_processor" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.aft_account_request_processor.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.aft_account_request_processor.arn
}

resource "aws_cloudwatch_log_group" "aft_account_request_processor" {
  name              = "/aws/lambda/${aws_lambda_function.aft_account_request_processor.function_name}"
  retention_in_days = var.cloudwatch_log_group_retention
  kms_key_id        = var.cloudwatch_log_group_enable_cmk_encryption ? aws_kms_key.aft.arn : null
}

resource "aws_sqs_queue" "aft_invoke_aft_account_provisioning_framework_dlq" {
  name                              = "aft-invoke-aft-account-provisioning-framework-dlq"
  kms_master_key_id                 = aws_kms_alias.aft.name
  kms_data_key_reuse_period_seconds = 300
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

  dead_letter_config {
    target_arn = aws_sqs_queue.aft_invoke_aft_account_provisioning_framework_dlq.arn
  }

  code_signing_config_arn = aws_lambda_code_signing_config.aft_invoke_aft_account_provisioning_framework.arn

  tracing_config {
    mode = "Active"
  }

  dynamic "vpc_config" {
    for_each = local.vpc_deployment ? [1] : []

    content {
      subnet_ids         = local.vpc_private_subnet_ids
      security_group_ids = tolist([aws_security_group.aft_vpc_default_sg[0].id])
    }
  }
}

resource "aws_signer_signing_profile" "aft_invoke_aft_account_provisioning_framework" {
  platform_id = "AWSLambda-SHA384-ECDSA"
}

resource "aws_lambda_code_signing_config" "aft_invoke_aft_account_provisioning_framework" {
  allowed_publishers {
    signing_profile_version_arns = [aws_signer_signing_profile.aft_invoke_aft_account_provisioning_framework.version_arn]
  }

  policies {
    untrusted_artifact_on_deployment = "Enforce"
  }
}

resource "aws_lambda_permission" "aft_invoke_aft_account_provisioning_framework" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.aft_invoke_aft_account_provisioning_framework.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.aft_controltower_event_trigger.arn
}

resource "aws_cloudwatch_log_group" "aft_invoke_aft_account_provisioning_framework" {
  name              = "/aws/lambda/${aws_lambda_function.aft_invoke_aft_account_provisioning_framework.function_name}"
  retention_in_days = var.cloudwatch_log_group_retention
  kms_key_id        = var.cloudwatch_log_group_enable_cmk_encryption ? aws_kms_key.aft.arn : null
}

resource "aws_sqs_queue" "aft_cleanup_resources_dlq" {
  name                              = "aft-cleanup-resources-dlq"
  kms_master_key_id                 = aws_kms_alias.aft.name
  kms_data_key_reuse_period_seconds = 300
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

  dead_letter_config {
    target_arn = aws_sqs_queue.aft_cleanup_resources_dlq.arn
  }

  code_signing_config_arn = aws_lambda_code_signing_config.aft_cleanup_resources.arn

  tracing_config {
    mode = "Active"
  }

  dynamic "vpc_config" {
    for_each = local.vpc_deployment ? [1] : []

    content {
      subnet_ids         = local.vpc_private_subnet_ids
      security_group_ids = tolist([aws_security_group.aft_vpc_default_sg[0].id])
    }
  }

}

resource "aws_signer_signing_profile" "aft_cleanup_resources" {
  platform_id = "AWSLambda-SHA384-ECDSA"
}

resource "aws_lambda_code_signing_config" "aft_cleanup_resources" {
  allowed_publishers {
    signing_profile_version_arns = [aws_signer_signing_profile.aft_cleanup_resources.version_arn]
  }

  policies {
    untrusted_artifact_on_deployment = "Enforce"
  }
}

resource "aws_cloudwatch_log_group" "aft_cleanup_resources" {
  name              = "/aws/lambda/${aws_lambda_function.aft_cleanup_resources.function_name}"
  retention_in_days = var.cloudwatch_log_group_retention
  kms_key_id        = var.cloudwatch_log_group_enable_cmk_encryption ? aws_kms_key.aft.arn : null
}


# Copyright Amazon.com, Inc. or its affiliates. All rights reserved.
# SPDX-License-Identifier: Apache-2.0
#
locals {
  lambda_managed_policies = [data.aws_iam_policy.AWSLambdaBasicExecutionRole.arn, data.aws_iam_policy.AWSLambdaVPCAccessExecutionRole.arn]
  orgs_endpoint_supported = data.aws_region.aft-management.region == "us-east-1" ? true : false

  vpc_private_route_table_ids = local.vpc_deployment ? try(data.aws_route_tables.aft_private_route_tables[0].ids, []) : []
  vpc_public_route_table_ids  = local.vpc_deployment ? try(data.aws_route_tables.aft_public_route_tables[0].ids, []) : []
  vpc_route_table_ids         = concat(local.vpc_private_route_table_ids, local.vpc_public_route_table_ids)

  vpc_private_subnet_ids = var.aft_enable_vpc || var.aft_customer_vpc_id != null ? concat(try(tolist([aws_subnet.aft_vpc_private_subnet_01[0].id, aws_subnet.aft_vpc_private_subnet_02[0].id]), []), var.aft_customer_private_subnets) : []
  vpc_public_subnet_ids = var.aft_enable_vpc && var.aft_customer_vpc_id == null ? tolist([aws_subnet.aft_vpc_public_subnet_01[0].id, aws_subnet.aft_vpc_public_subnet_02[0].id]) : []

  vpc_cidr       = local.vpc_deployment ? data.aws_vpc.aft[0].cidr_block : null
  vpc_deployment = var.aft_enable_vpc || var.aft_customer_vpc_id != null ? true : false
  vpc_id         = var.aft_enable_vpc || var.aft_customer_vpc_id != null ? try(aws_vpc.aft_vpc[0].id, var.aft_customer_vpc_id) : null
}


# Copyright Amazon.com, Inc. or its affiliates. All rights reserved.
# SPDX-License-Identifier: Apache-2.0
#
output "sns_topic_arn" {
  description = "ARN of aft notifications sns topic"
  value       = aws_sns_topic.aft_notifications.arn
}

output "failure_sns_topic_arn" {
  description = "ARN of failure_notifications sns topic"
  value       = aws_sns_topic.aft_failure_notifications.arn
}

output "aft_kms_key_arn" {
  description = "ARN for the AFT CMK Key"
  value       = aws_kms_key.aft.arn
}

output "aft_kms_key_id" {
  description = "ID for the AFT CMK Key"
  value       = aws_kms_key.aft.id
}

output "aft_kms_key_alias_arn" {
  description = "ARN for the AFT CMK Key alias"
  value       = aws_kms_alias.aft.id
}

output "request_action_trigger_function_arn" {
  value = aws_lambda_function.aft_account_request_action_trigger.arn
}

output "request_audit_trigger_function_arn" {
  value = aws_lambda_function.aft_account_request_audit_trigger.arn
}

output "request_processor_function_arn" {
  value = aws_lambda_function.aft_account_request_processor.arn
}

output "control_tower_event_logger_function_arn" {
  value = aws_lambda_function.aft_controltower_event_logger.arn
}

output "invoke_aft_account_provisioning_framework_function_arn" {
  value = aws_lambda_function.aft_invoke_aft_account_provisioning_framework.arn
}

output "request_queue_name" {
  value = aws_sqs_queue.aft_account_request.name
}
output "request_table_name" {
  value = aws_dynamodb_table.aft_request.name
}
output "request_audit_table_name" {
  value = aws_dynamodb_table.aft_request_audit.name
}
output "request_metadata_table_name" {
  value = aws_dynamodb_table.aft_request_metadata.name
}
output "controltower_events_table_name" {
  value = aws_dynamodb_table.aft_controltower_events.name
}
output "account_factory_product_name" {
  value = var.account_factory_product_name
}
output "invoke_aft_account_provisioning_framework_lambda_function_name" {
  value = aws_lambda_function.aft_invoke_aft_account_provisioning_framework.function_name
}
output "aft_cleanup_resources_function_name" {
  value = aws_lambda_function.aft_cleanup_resources.function_name
}
output "aft_account_provisioning_framework_sfn_name" {
  value = var.aft_account_provisioning_framework_sfn_name
}
output "aft_sns_topic_arn" {
  value = aws_sns_topic.aft_notifications.arn
}
output "aft_failure_sns_topic_arn" {
  value = aws_sns_topic.aft_failure_notifications.arn
}

output "aft_vpc_id" {
  value = local.vpc_deployment ? local.vpc_id : null
}

output "aft_vpc_public_subnets" {
  value = local.vpc_public_subnet_ids
}

output "aft_vpc_private_subnets" {
  value = local.vpc_deployment ? local.vpc_private_subnet_ids : null
}

output "aft_vpc_default_sg" {
  value = local.vpc_deployment ? tolist([aws_security_group.aft_vpc_default_sg[0].id]) : null
}

output "vpc_deployment" {
  value = local.vpc_deployment
}


# Copyright Amazon.com, Inc. or its affiliates. All rights reserved.
# SPDX-License-Identifier: Apache-2.0
#
resource "aws_sns_topic" "aft_notifications" {
  name = "aft-notifications"
  kms_master_key_id = var.sns_topic_enable_cmk_encryption ? aws_kms_key.aft.id : "alias/aws/sns"
}

resource "aws_sns_topic" "aft_failure_notifications" {
  name = "aft-failure-notifications"
  kms_master_key_id = var.sns_topic_enable_cmk_encryption ? aws_kms_key.aft.id : "alias/aws/sns"
}


# Copyright Amazon.com, Inc. or its affiliates. All rights reserved.
# SPDX-License-Identifier: Apache-2.0
#
resource "aws_sqs_queue" "aft_account_request" {
  name                              = "aft-account-request.fifo"
  fifo_queue                        = true
  kms_master_key_id                 = aws_kms_alias.aft.name
  visibility_timeout_seconds        = 240
  kms_data_key_reuse_period_seconds = 300
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.aft_account_request_dlq.arn
    maxReceiveCount     = 1
  })
}

resource "aws_sqs_queue" "aft_account_request_dlq" {
  name                              = "aft-account-request-dlq.fifo"
  fifo_queue                        = true
  kms_master_key_id                 = aws_kms_alias.aft.name
  kms_data_key_reuse_period_seconds = 300
}


# Copyright Amazon.com, Inc. or its affiliates. All rights reserved.
# SPDX-License-Identifier: Apache-2.0
#
variable "account_factory_product_name" {
  type = string
}

variable "cloudwatch_log_group_retention" {
  type = string
}

variable "cloudwatch_log_group_enable_cmk_encryption" {
  type = bool
}

variable "aft_account_provisioning_framework_sfn_name" {
  type = string
}

variable "aft_common_layer_arn" {
  type = string
}

variable "aft_vpc_cidr" {
  type    = string
  default = null
}

variable "aft_vpc_private_subnet_01_cidr" {
  type    = string
  default = null
}

variable "aft_vpc_private_subnet_02_cidr" {
  type    = string
  default = null
}

variable "aft_vpc_public_subnet_01_cidr" {
  type    = string
  default = null
}

variable "aft_vpc_public_subnet_02_cidr" {
  type    = string
  default = null
}

variable "aft_vpc_endpoints" {
  type    = bool
  default = null
}

variable "request_framework_archive_path" {
  type = string
}

variable "request_framework_archive_hash" {
  type = string
}
variable "concurrent_account_factory_actions" {
  type = number
}

variable "lambda_runtime_python_version" {
  type = string
}

variable "backup_recovery_point_retention" {
  type = number
}

variable "aft_enable_vpc" {
  type = bool
}

variable "aft_customer_vpc_id" {
  type = string
}

variable "aft_customer_private_subnets" {
  type = list(string)
}

variable "sns_topic_enable_cmk_encryption" {
  type = bool
}


# Copyright Amazon.com, Inc. or its affiliates. All rights reserved.
# SPDX-License-Identifier: Apache-2.0
#
terraform {
  required_version = ">= 1.2.0, < 2.0.0"

  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = ">= 4.9.0"
      configuration_aliases = [aws.ct_management]
    }
  }
}


# Copyright Amazon.com, Inc. or its affiliates. All rights reserved.
# SPDX-License-Identifier: Apache-2.0
#

resource "aws_vpc" "aft_vpc" {
  count                = var.aft_enable_vpc && var.aft_customer_vpc_id == null ? 1 : 0
  cidr_block           = var.aft_vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = "aft-management-vpc"
  }
}

resource "aws_flow_log" "aft_vpc" {
  count                = var.aft_enable_vpc && var.aft_customer_vpc_id == null ? 1 : 0
  iam_role_arn         = aws_iam_role.aft_vpc_flow_log[0].arn
  log_destination      = aws_cloudwatch_log_group.aft_vpc_flow_log[0].arn
  traffic_type         = "ALL"
  vpc_id               = aws_vpc.aft_vpc[0].id
}

resource "aws_cloudwatch_log_group" "aft_vpc_flow_log" {
  count             = var.aft_enable_vpc && var.aft_customer_vpc_id == null ? 1 : 0
  name              = "/aws/vpc/aft-vpc-flow-logs"
  retention_in_days = var.cloudwatch_log_group_retention
  kms_key_id        = var.cloudwatch_log_group_enable_cmk_encryption ? aws_kms_key.aft.arn : null
}

resource "aws_iam_role" "aft_vpc_flow_log" {
  count = var.aft_enable_vpc && var.aft_customer_vpc_id == null ? 1 : 0
  name  = "aft-vpc-flow-log-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "vpc-flow-logs.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "aft_vpc_flow_log" {
  count = var.aft_enable_vpc && var.aft_customer_vpc_id == null ? 1 : 0
  name  = "aft-vpc-flow-log-policy"
  role  = aws_iam_role.aft_vpc_flow_log[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Effect   = "Allow"
        Resource = "*"
      }
    ]
  })
}

resource "aws_default_security_group" "aft_vpc_default_sg" {
  count  = var.aft_enable_vpc && var.aft_customer_vpc_id == null ? 1 : 0
  vpc_id = aws_vpc.aft_vpc[0].id
  tags = {
    Name = "aft-vpc-default-sg"
  }
}

resource "aws_subnet" "aft_vpc_private_subnet_01" {
  count             = var.aft_enable_vpc && var.aft_customer_vpc_id == null ? 1 : 0
  vpc_id            = aws_vpc.aft_vpc[0].id
  cidr_block        = var.aft_vpc_private_subnet_01_cidr
  availability_zone = element(data.aws_availability_zones.available.names, 0)
  tags = {
    Name = "aft-vpc-private-subnet-01"
  }
}

resource "aws_subnet" "aft_vpc_private_subnet_02" {
  count             = var.aft_enable_vpc && var.aft_customer_vpc_id == null ? 1 : 0
  vpc_id            = aws_vpc.aft_vpc[0].id
  cidr_block        = var.aft_vpc_private_subnet_02_cidr
  availability_zone = element(data.aws_availability_zones.available.names, 1)
  tags = {
    Name = "aft-vpc-private-subnet-02"
  }
}

resource "aws_subnet" "aft_vpc_public_subnet_01" {
  count             = var.aft_enable_vpc && var.aft_customer_vpc_id == null ? 1 : 0
  vpc_id            = aws_vpc.aft_vpc[0].id
  cidr_block        = var.aft_vpc_public_subnet_01_cidr
  availability_zone = element(data.aws_availability_zones.available.names, 0)
  tags = {
    Name = "aft-vpc-public-subnet-01"
  }
}

resource "aws_subnet" "aft_vpc_public_subnet_02" {
  count             = var.aft_enable_vpc && var.aft_customer_vpc_id == null ? 1 : 0
  vpc_id            = aws_vpc.aft_vpc[0].id
  cidr_block        = var.aft_vpc_public_subnet_02_cidr
  availability_zone = element(data.aws_availability_zones.available.names, 1)
  tags = {
    Name = "aft-vpc-public-subnet-02"
  }
}

resource "aws_route_table" "aft_vpc_private_subnet_01" {
  count  = var.aft_enable_vpc && var.aft_customer_vpc_id == null ? 1 : 0
  vpc_id = aws_vpc.aft_vpc[0].id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.aft-vpc-natgw-01[0].id
  }
  tags = {
    Name = "aft-vpc-private-subnet-01"
  }
}

resource "aws_route_table" "aft_vpc_private_subnet_02" {
  count  = var.aft_enable_vpc && var.aft_customer_vpc_id == null ? 1 : 0
  vpc_id = aws_vpc.aft_vpc[0].id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.aft-vpc-natgw-02[0].id
  }
  tags = {
    Name = "aft-vpc-private-subnet-02"
  }
}

resource "aws_route_table" "aft_vpc_public_subnet_01" {
  count  = var.aft_enable_vpc && var.aft_customer_vpc_id == null ? 1 : 0
  vpc_id = aws_vpc.aft_vpc[0].id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.aft-vpc-igw[0].id
  }
  tags = {
    Name = "aft-vpc-public-subnet-01"
  }
}

resource "aws_route_table_association" "aft_vpc_private_subnet_01" {
  count          = var.aft_enable_vpc && var.aft_customer_vpc_id == null ? 1 : 0
  subnet_id      = aws_subnet.aft_vpc_private_subnet_01[0].id
  route_table_id = aws_route_table.aft_vpc_private_subnet_01[0].id
}

resource "aws_route_table_association" "aft_vpc_private_subnet_02" {
  count          = var.aft_enable_vpc && var.aft_customer_vpc_id == null ? 1 : 0
  subnet_id      = aws_subnet.aft_vpc_private_subnet_02[0].id
  route_table_id = aws_route_table.aft_vpc_private_subnet_02[0].id
}

resource "aws_route_table_association" "aft_vpc_public_subnet_01" {
  count          = var.aft_enable_vpc && var.aft_customer_vpc_id == null ? 1 : 0
  subnet_id      = aws_subnet.aft_vpc_public_subnet_01[0].id
  route_table_id = aws_route_table.aft_vpc_public_subnet_01[0].id
}

resource "aws_route_table_association" "aft_vpc_public_subnet_02" {
  count          = var.aft_enable_vpc && var.aft_customer_vpc_id == null ? 1 : 0
  subnet_id      = aws_subnet.aft_vpc_public_subnet_02[0].id
  route_table_id = aws_route_table.aft_vpc_public_subnet_01[0].id
}

resource "aws_security_group" "aft_vpc_default_sg" {
  count       = var.aft_enable_vpc || var.aft_customer_vpc_id != null ? 1 : 0
  name        = "aft-default-sg"
  description = "Allow outbound traffic"
  vpc_id      = local.vpc_id

  egress {
    description = "Allow outbound HTTPS traffic"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "aft_vpc_endpoint_sg" {
  count       = var.aft_enable_vpc || var.aft_customer_vpc_id != null ? 1 : 0
  name        = "aft-endpoint-sg"
  description = "Allow inbound HTTPS traffic and all Outbound"
  vpc_id      = local.vpc_id

  ingress {
    description = "Allow inbound TLS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [local.vpc_cidr]
  }

  ingress {
    description = "Allow inbound SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [local.vpc_cidr]
  }

  egress {
    description = "Allow outbound HTTPS traffic"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_internet_gateway" "aft-vpc-igw" {
  count  = var.aft_enable_vpc && var.aft_customer_vpc_id == null ? 1 : 0
  vpc_id = aws_vpc.aft_vpc[0].id

  tags = {
    Name = "aft-vpc-igw"
  }
}

resource "aws_eip" "aft-vpc-natgw-01" {
  count  = var.aft_enable_vpc && var.aft_customer_vpc_id == null ? 1 : 0
  domain = "vpc"
}

resource "aws_eip" "aft-vpc-natgw-02" {
  count  = var.aft_enable_vpc && var.aft_customer_vpc_id == null ? 1 : 0
  domain = "vpc"
}

resource "aws_nat_gateway" "aft-vpc-natgw-01" {
  count      = var.aft_enable_vpc && var.aft_customer_vpc_id == null ? 1 : 0
  depends_on = [aws_internet_gateway.aft-vpc-igw]

  allocation_id = aws_eip.aft-vpc-natgw-01[0].id
  subnet_id     = aws_subnet.aft_vpc_public_subnet_01[0].id

  tags = {
    Name = "aft-vpc-natgw-01"
  }

}

resource "aws_nat_gateway" "aft-vpc-natgw-02" {
  count      = var.aft_enable_vpc && var.aft_customer_vpc_id == null ? 1 : 0
  depends_on = [aws_internet_gateway.aft-vpc-igw]

  allocation_id = aws_eip.aft-vpc-natgw-02[0].id
  subnet_id     = aws_subnet.aft_vpc_public_subnet_02[0].id

  tags = {
    Name = "aft-vpc-natgw-02"
  }

}

resource "aws_vpc_endpoint" "s3" {
  count = local.vpc_deployment && var.aft_vpc_endpoints ? 1 : 0

  vpc_id            = local.vpc_id
  vpc_endpoint_type = "Gateway"
  service_name      = "com.amazonaws.${data.aws_region.aft-management.region}.s3"
  route_table_ids   = local.vpc_route_table_ids
}

resource "aws_vpc_endpoint" "dynamodb" {
  count = local.vpc_deployment && var.aft_vpc_endpoints ? 1 : 0

  vpc_id            = local.vpc_id
  vpc_endpoint_type = "Gateway"
  service_name      = "com.amazonaws.${data.aws_region.aft-management.region}.dynamodb"
  route_table_ids   = local.vpc_route_table_ids
}

resource "aws_vpc_endpoint" "codebuild" {
  count = local.vpc_deployment && var.aft_vpc_endpoints ? 1 : 0

  vpc_id            = local.vpc_id
  service_name      = data.aws_vpc_endpoint_service.codebuild[0].service_name
  vpc_endpoint_type = "Interface"
  subnet_ids        = data.aws_subnets.codebuild[0].ids
  security_group_ids = [
    aws_security_group.aft_vpc_endpoint_sg[0].id,
  ]

  private_dns_enabled = true
}

resource "aws_vpc_endpoint" "codecommit" {
  count = local.vpc_deployment && var.aft_vpc_endpoints ? 1 : 0

  vpc_id            = local.vpc_id
  service_name      = data.aws_vpc_endpoint_service.codecommit[0].service_name
  vpc_endpoint_type = "Interface"
  subnet_ids        = data.aws_subnets.codecommit[0].ids
  security_group_ids = [
    aws_security_group.aft_vpc_endpoint_sg[0].id,
  ]

  private_dns_enabled = true
}

resource "aws_vpc_endpoint" "git-codecommit" {
  count = local.vpc_deployment && var.aft_vpc_endpoints ? 1 : 0

  vpc_id            = local.vpc_id
  service_name      = data.aws_vpc_endpoint_service.git-codecommit[0].service_name
  vpc_endpoint_type = "Interface"
  subnet_ids        = data.aws_subnets.git-codecommit[0].ids
  security_group_ids = [
    aws_security_group.aft_vpc_endpoint_sg[0].id,
  ]

  private_dns_enabled = true
}

resource "aws_vpc_endpoint" "codepipeline" {
  count = local.vpc_deployment && var.aft_vpc_endpoints ? 1 : 0

  vpc_id            = local.vpc_id
  service_name      = data.aws_vpc_endpoint_service.codepipeline[0].service_name
  vpc_endpoint_type = "Interface"
  subnet_ids        = data.aws_subnets.codepipeline[0].ids
  security_group_ids = [
    aws_security_group.aft_vpc_endpoint_sg[0].id,
  ]

  private_dns_enabled = true
}

resource "aws_vpc_endpoint" "servicecatalog" {
  count = local.vpc_deployment && var.aft_vpc_endpoints ? 1 : 0

  vpc_id            = local.vpc_id
  service_name      = data.aws_vpc_endpoint_service.servicecatalog[0].service_name
  vpc_endpoint_type = "Interface"
  subnet_ids        = data.aws_subnets.servicecatalog[0].ids
  security_group_ids = [
    aws_security_group.aft_vpc_endpoint_sg[0].id,
  ]

  private_dns_enabled = true
}

resource "aws_vpc_endpoint" "lambda" {
  count = local.vpc_deployment && var.aft_vpc_endpoints ? 1 : 0

  vpc_id            = local.vpc_id
  service_name      = data.aws_vpc_endpoint_service.lambda[0].service_name
  vpc_endpoint_type = "Interface"
  subnet_ids        = data.aws_subnets.lambda[0].ids
  security_group_ids = [
    aws_security_group.aft_vpc_endpoint_sg[0].id,
  ]

  private_dns_enabled = true
}

resource "aws_vpc_endpoint" "kms" {
  count = local.vpc_deployment && var.aft_vpc_endpoints ? 1 : 0

  vpc_id            = local.vpc_id
  service_name      = data.aws_vpc_endpoint_service.kms[0].service_name
  vpc_endpoint_type = "Interface"
  subnet_ids        = data.aws_subnets.kms[0].ids
  security_group_ids = [
    aws_security_group.aft_vpc_endpoint_sg[0].id,
  ]

  private_dns_enabled = true
}

resource "aws_vpc_endpoint" "logs" {
  count = local.vpc_deployment && var.aft_vpc_endpoints ? 1 : 0

  vpc_id            = local.vpc_id
  service_name      = data.aws_vpc_endpoint_service.logs[0].service_name
  vpc_endpoint_type = "Interface"
  subnet_ids        = data.aws_subnets.logs[0].ids
  security_group_ids = [
    aws_security_group.aft_vpc_endpoint_sg[0].id,
  ]

  private_dns_enabled = true
}

resource "aws_vpc_endpoint" "events" {
  count = local.vpc_deployment && var.aft_vpc_endpoints ? 1 : 0

  vpc_id            = local.vpc_id
  service_name      = data.aws_vpc_endpoint_service.events[0].service_name
  vpc_endpoint_type = "Interface"
  subnet_ids        = data.aws_subnets.events[0].ids
  security_group_ids = [
    aws_security_group.aft_vpc_endpoint_sg[0].id,
  ]

  private_dns_enabled = true
}

resource "aws_vpc_endpoint" "organizations" {
  count = local.vpc_deployment && var.aft_vpc_endpoints && local.orgs_endpoint_supported ? 1 : 0

  vpc_id            = local.vpc_id
  service_name      = data.aws_vpc_endpoint_service.organizations[0].service_name
  vpc_endpoint_type = "Interface"
  subnet_ids        = data.aws_subnets.organizations[0].ids
  security_group_ids = [
    aws_security_group.aft_vpc_endpoint_sg[0].id,
  ]

  private_dns_enabled = true
}

resource "aws_vpc_endpoint" "states" {
  count = local.vpc_deployment && var.aft_vpc_endpoints ? 1 : 0

  vpc_id            = local.vpc_id
  service_name      = data.aws_vpc_endpoint_service.states[0].service_name
  vpc_endpoint_type = "Interface"
  subnet_ids        = data.aws_subnets.states[0].ids
  security_group_ids = [
    aws_security_group.aft_vpc_endpoint_sg[0].id,
  ]

  private_dns_enabled = true
}

resource "aws_vpc_endpoint" "ssm" {
  count = local.vpc_deployment && var.aft_vpc_endpoints ? 1 : 0

  vpc_id            = local.vpc_id
  service_name      = data.aws_vpc_endpoint_service.ssm[0].service_name
  vpc_endpoint_type = "Interface"
  subnet_ids        = data.aws_subnets.ssm[0].ids
  security_group_ids = [
    aws_security_group.aft_vpc_endpoint_sg[0].id,
  ]

  private_dns_enabled = true
}

resource "aws_vpc_endpoint" "sns" {
  count = local.vpc_deployment && var.aft_vpc_endpoints ? 1 : 0

  vpc_id            = local.vpc_id
  service_name      = data.aws_vpc_endpoint_service.sns[0].service_name
  vpc_endpoint_type = "Interface"
  subnet_ids        = data.aws_subnets.sns[0].ids
  security_group_ids = [
    aws_security_group.aft_vpc_endpoint_sg[0].id,
  ]

  private_dns_enabled = true
}

resource "aws_vpc_endpoint" "sqs" {
  count = local.vpc_deployment && var.aft_vpc_endpoints ? 1 : 0

  vpc_id            = local.vpc_id
  service_name      = data.aws_vpc_endpoint_service.sqs[0].service_name
  vpc_endpoint_type = "Interface"
  subnet_ids        = data.aws_subnets.sqs[0].ids
  security_group_ids = [
    aws_security_group.aft_vpc_endpoint_sg[0].id,
  ]

  private_dns_enabled = true
}

resource "aws_vpc_endpoint" "sts" {
  count = local.vpc_deployment && var.aft_vpc_endpoints ? 1 : 0

  vpc_id            = local.vpc_id
  service_name      = data.aws_vpc_endpoint_service.sts[0].service_name
  vpc_endpoint_type = "Interface"
  subnet_ids        = data.aws_subnets.sts[0].ids
  security_group_ids = [
    aws_security_group.aft_vpc_endpoint_sg[0].id,
  ]

  private_dns_enabled = true
}