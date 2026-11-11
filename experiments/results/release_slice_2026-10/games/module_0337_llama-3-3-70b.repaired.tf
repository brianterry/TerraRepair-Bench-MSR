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

  # Explicit workaround due to https://github.com/hashicorp/terraform-provider-aws/issues/22595
  condition {}
  not_resources = []

}


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
    name   = "zone-type"
    values = ["availability-zone"]
  }
}

data "aws_vpc" "aft" {
  count = local.vpc_deployment ? 1 : 0

  id = local.vpc_id
}

# Lookup route tables associated to customer provided subnets 
# for Gateway endpoint deployments
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

######################################
# VPC Endpoints
######################################

#### CodeBuild ####

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

#### CodeCommit ####

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

#### git-codecommit ####

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

#### codepipeline ####

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

#### servicecatalog ####

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

#### lambda ####

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

#### kms ####

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

#### logs ####

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

#### events ####

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

#### organizations ####

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

#### states ####

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

#### ssm ####

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

#### sns ####

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

#### sqs ####

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

#### sts ####

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


resource "aws_kms_key" "aft" {
  description         = "AFT KMS key"
  enable_key_rotation = "true"
  # Use inline policy instead of 'aws_kms_key_policy' resource
  # to always make sure policy is fully propagated before the key is used
  # e.g. for CloudWatch Log Groups
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
          "Sid" : "Allow CloudWatch Logs access", # Reference: https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/encrypt-log-data-kms.html
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
              # Allow all log groups in AFT Mgmt Account
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
  dead_letter_config {
    type = "SQS"
    arn  = aws_sqs_queue.aft_account_request_dlq.arn
  }
  reserved_concurrent_executions = 1
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
  dead_letter_config {
    type = "SQS"
    arn  = aws_sqs_queue.aft_account_request_dlq.arn
  }
  reserved_concurrent_executions = 1
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
  dead_letter_config {
    type = "SQS"
    arn