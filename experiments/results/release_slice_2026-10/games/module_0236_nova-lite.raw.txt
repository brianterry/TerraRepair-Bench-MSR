```hcl
data "aws_caller_identity" "mod-platform" {
  provider = aws.modernisation-platform
}

data "aws_kms_alias" "environment_management" {
  provider = aws.modernisation-platform
  name     = "alias/environment-management-multi-region"
}

#S3 Bucket for Athena temp SQL queries 

module "s3-bucket-athena" {
  source = "github.com/ministryofjustice/modernisation-platform-terraform-s3-bucket?ref=9facf9fc8f8b8e3f93ffbda822028534b9a75399" # v9.0.0
  providers = {
    aws.bucket-replication = aws.modernisation-platform-eu-west-1
  }
  bucket_policy       = [data.aws_iam_policy_document.athena_bucket_policy.json]
  bucket_name         = "athena-cloudtrail-query"
  custom_kms_key      = aws_kms_key.s3_logging_cloudtrail.arn
  replication_enabled = false
  lifecycle_rule = [
    {
      id      = "main"
      enabled = "Enabled"
      prefix  = ""
      tags    = {}
      expiration = {
        days = 7
      }
    }
  ]
  tags = local.tags
  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "aws:kms"
        kms_master_key_id = aws_kms_key.s3_logging_cloudtrail.arn
      }
    }
  }
}

data "aws_iam_policy_document" "athena_bucket_policy" {
  statement {
    sid    = "AllowListBucketACL"
    effect = "Allow"
    actions = [
      "s3:PutObject",
      "s3:GetObject",
      "s3:GetBucketLogging",
      "s3:ListBucketVersions",
      "s3:ListBucket",
      "s3:GetEncryptionConfiguration",
      "s3:GetBucketAcl",
      "s3:GetBucketPolicy"
    ]
    resources = [module.s3-bucket-athena.bucket.arn,
    format("%s/*", module.s3-bucket-athena.bucket.arn)]
    principals {
      type        = "Service"
      identifiers = ["s3.amazonaws.com"]
    }

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "athena_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_athena_workgroup" "mod-platform" {
  name = "mod-platform"

  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = true

    result_configuration {
      output_location = "s3://${module.s3-bucket-athena.bucket.id}/"
      encryption_configuration {
        encryption_option = "SSE_KMS"
        kms_key           = aws_kms_key.s3_logging_cloudtrail.arn
      }
    }
  }
}

resource "aws_iam_role" "athena_lambda" {
  name               = "athena_lambda"
  assume_role_policy = data.aws_iam_policy_document.athena_assume_role_policy.json
}

resource "aws_iam_policy" "athena_lambda_policy" {
  name = "athena_lambda_policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "glue:GetDatabase",
          "glue:GetTable",
          "glue:GetTables",
          "glue:CreateTable",
          "glue:CreateDatabase",
          "glue:CreateSchema",
          "glue:CreatePartition",
          "glue:GetDatabases",
          "glue:GetPartitions",
          "glue:DeleteTable"
        ]
        Effect   = "Allow"
        Resource = "*"
      },
      {
        Action = [
          "athena:StartQueryExecution",
        ]
        Effect = "Allow"
        Resource = [
          aws_athena_workgroup.mod-platform.arn,
          format("arn:aws:athena:eu-west-2:%s:workgroup/primary", data.aws_caller_identity.current.account_id)
        ]
      },
      {
        Action = [
          "secretsmanager:GetSecretValue",
        ]
        Effect   = "Allow"
        Resource = "arn:aws:secretsmanager:eu-west-2:${data.aws_caller_identity.modernisation-platform.account_id}:secret:environment_management*"
      },
      {
        Action = [
          "ssm:GetParameter"
        ]
        Effect   = "Allow"
        Resource = "arn:aws:ssm:eu-west-2:${data.aws_caller_identity.current.account_id}:parameter/environment_management_arn"
      },
      {
        Action = [
          "kms:Decrypt*",
          "kms:GenerateDataKey"
        ]
        Effect = "Allow"
        Resource = [
          aws_kms_key.s3_logging_cloudtrail.arn,
          aws_kms_key.athena_logging.arn,
          data.aws_kms_alias.environment_management.target_key_arn
        ]
      },
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Effect   = "Allow"
        Resource = "arn:aws:logs:eu-west-2:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/athena_table_update:*"
      },
      {
        Action = [
          "s3:*Object",
          "s3:GetBucketLocation",
          "s3:List*"
        ]
        Effect = "Allow"
        Resource = [
          "${module.s3-bucket-athena.bucket.arn}/*",
          module.s3-bucket-athena.bucket.arn
        ]
      },
      {
        Action = [
          "s3:GetBucketLocation",
          "s3:List*",
          "s3:Get*"
        ]
        Effect = "Allow"
        Resource = [
          module.s3-bucket-cloudtrail-logging.bucket.arn,
          "${module.s3-bucket-cloudtrail-logging.bucket.arn}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "athena_lambda_policy_attachment" {
  role       = aws_iam_role.athena_lambda.name
  policy_arn = aws_iam_policy.athena_lambda_policy.arn
}

#Create ZIP archive and lambda
data "archive_file" "lambda_zip" {

  depends_on = [module.s3-bucket-athena]

  type        = "zip"
  source_file = "lambda/index.py"
  output_path = "lambda/lambda_function.zip"
}

resource "aws_kms_key" "athena_logging" {
  enable_key_rotation = true
  policy              = data.aws_iam_policy_document.athena_logging.json
  tags                = { Name = "${local.application_name}-athena-kms" }
}

resource "aws_kms_alias" "athena_logging" {
  name          = "alias/athena-logging"
  target_key_id = aws_kms_key.athena_logging.key_id
}

data "aws_iam_policy_document" "athena_logging" {
  # checkov:skip=CKV_AWS_111: "policy is directly related to the resource"
  # checkov:skip=CKV_AWS_356: "policy is directly related to the resource"
  # checkov:skip=CKV_AWS_109: "role is resticted by limited actions in member account"

  # -- AWS - Documentation reference --
  # Resource – (Required) In a key policy, the value of the Resource element is "*", 
  # which means "this KMS key." The asterisk ("*") identifies the KMS key to which the key policy is attached. 

  statement {
    sid    = "Allow management access of the key to the logging account"
    effect = "Allow"
    actions = [
      "kms:*"
    ]
    resources = [
      "*"
    ]
    principals {
      type = "AWS"
      identifiers = [
        data.aws_caller_identity.current.account_id
      ]
    }
  }
  statement {
    sid    = "Allow use of the key including encryption"
    effect = "Allow"
    actions = [
      "kms:Decrypt*"
    ]
    resources = [
      "*"
    ]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_lambda_function" "athena_table_update" {
  # checkov:skip=CKV_AWS_50: "X-ray tracing is not required"
  # checkov:skip=CKV_AWS_117: "Lambda is not environment specific"
  # checkov:skip=CKV_AWS_116: "DLQ not required"
  # checkov:skip=CKV_AWS_272: "Code signing not required"
  depends_on = [
    module.s3-bucket-athena

  ]

  filename                       = "lambda/lambda_function.zip"
  function_name                  = "athena_table_update"
  role                           = aws_iam_role.athena_lambda.arn
  handler                        = "index.lambda_handler"
  source_code_hash               = data.archive_file.lambda_zip.output_base64sha256
  runtime                        = "python3.12"
  reserved_concurrent_executions = 1
  kms_key_arn                    = aws_kms_key.athena_logging.arn
  environment {
    variables = {
      mod_account = data.aws_caller_identity.mod-platform.account_id
    }
  }
  tracing_config {
    mode = "Active"
  }
}

resource "aws_cloudwatch_event_rule" "every_day" {
  name                = "run-daily"
  description         = "Runs daily at 12:15"
  schedule_expression = "cron(15 0 * *? *)"
}

resource "aws_cloudwatch_event_target" "trigger_lamber_every_day" {
  rule      = aws_cloudwatch_event_rule.every_day.name
  target_id = "athena_table_update"
  arn       = aws_lambda_function.athena_table_update.arn
}

resource "aws_lambda_permission" "allow_cloudwatch_to_call_lambda" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.athena_table_update.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.every_day.arn
}

# Backend
terraform {
  # `backend` blocks do not support variables, so the following are hard-coded here:
  # - S3 bucket name, which is created in modernisation-platform-account/s3.tf
  backend "s3" {
    acl                  = "bucket-owner-full-control"
    bucket               = "modernisation-platform-terraform-state"
    encrypt              = true
    key                  = "terraform.tfstate"
    region               = "eu-west-2"
    use_lockfile         = true
    workspace_key_prefix = "environments/accounts/core-logging" # This will store the object as environments/core-logging/${workspace}/terraform.tfstate
  }
}


variable "networking" {
  type = list(any)
  default = [
    {
      "business-unit" : "",
      "set" : "",
      "application" : "core-logging"
    }
  ]
}

data "aws_organizations_organization" "moj_root_account" {}
data "aws_organizations_organization" "current" {}
data "aws_region" "current" {}


locals {
  github_workflow_poller = {
    enabled             = true
    github_owner        = "ministryofjustice"
    github_repo         = "modernisation-platform"
    lookback_hours      = 2
    schedule_expression = "cron(0/15 * * *? *)"
    log_retention_days  = 90
  }
}

resource "aws_cloudwatch_log_group" "github_workflow_data" {
  count             = local.github_workflow_poller.enabled? 1 : 0
  name              = "modernisation-platform-workflow-data"
  retention_in_days = local.github_workflow_poller.log_retention_days
  kms_key_id        = aws_kms_alias.moj_cur_reports.arn

  tags = merge(
    local.tags,
    {
      Name = "modernisation-platform-workflow-data"
    }
  )
}

resource "aws_cloudwatch_log_group" "github_workflow_poller_lambda" {
  count             = local.github_workflow_poller.enabled? 1 : 0
  name              = "/aws/lambda/github-workflow-data-poller"
  retention_in_days = local.github_workflow_poller.log_retention_days
  kms_key_id        = aws_kms_alias.moj_cur_reports.arn

  tags = merge(
    local.tags,
    {
      Name = "github-workflow-data-poller-logs"
    }
  )
}

resource "aws_iam_role" "github_workflow_poller_lambda" {
  count = local.github_workflow_poller.enabled? 1 : 0
  name  = "github-workflow-data-poller-lambda"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = local.tags
}

resource "aws_iam_role_policy" "github_workflow_poller_lambda" {
  count = local.github_workflow_poller.enabled? 1 : 0
  name  = "github-workflow-data-poller-lambda-policy"
  role  = aws_iam_role.github_workflow_poller_lambda[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = [
          "${aws_cloudwatch_log_group.github_workflow_poller_lambda[0].arn}:*",
          "${aws_cloudwatch_log_group.github_workflow_data[0].arn}:*"
        ]
      }
    ]
  })
}

data "archive_file" "github_workflow_poller_lambda" {
  count       = local.github_workflow_poller.enabled? 1 : 0
  type        = "zip"
  source_file = "${path.module}/lambda/github_workflow_data_poller/github_workflow_data_poller.py"
  output_path = "${path.module}/lambda/github_workflow_data_poller/lambda.zip"
}

resource "aws_lambda_function" "github_workflow_data_poller" {
  count                          = local.github_workflow_poller.enabled? 1 : 0
  filename                       = data.archive_file.github_workflow_poller_lambda[0].output_path
  function_name                  = "github-workflow-data-poller"
  role                           = aws_iam_role.github_workflow_poller_lambda[0].arn
  handler                        = "github_workflow_data_poller.lambda_handler"
  source_code_hash               = data.archive_file.github_workflow_poller_lambda[0].output_base64sha256
  runtime                        = "python3.12"
  timeout                        = 300
  description                    = "Polls GitHub Actions workflow data and writes to CloudWatch Logs"
  reserved_concurrent_executions = 10

  environment {
    variables = {
      GITHUB_OWNER           = local.github_workflow_poller.github_owner
      GITHUB_REPO            = local.github_workflow_poller.github_repo
      LOOKBACK_HOURS         = local.github_workflow_poller.lookback_hours
      WORKFLOW_RUN_LOG_GROUP = aws_cloudwatch_log_group.github_workflow_data[0].name
      GITHUB_TOKEN           = "" # Optional: Add if you need authenticated API access
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.github_workflow_poller_lambda,
    aws_iam_role_policy.github_workflow_poller_lambda
  ]

  tags = merge(
    local.tags,
    {
      Name = "github-workflow-data-poller"
    }
  )
  tracing_config {
    mode = "Active"
  }
}

resource "aws_cloudwatch_event_rule" "github_workflow_poller" {
  count               = local.github_workflow_poller.enabled? 1 : 0
  name                = "github-workflow-data-poller"
  description         = "Trigger GitHub workflow data poller"
  schedule_expression = local.github_workflow_poller.schedule_expression

  tags = local.tags
}

resource "aws_cloudwatch_event_target" "github_workflow_poller" {
  count = local.github_workflow_poller.enabled? 1 : 0
  rule  = aws_cloudwatch_event_rule.github_workflow_poller[0].name
  arn   = aws_lambda_function.github_workflow_data_poller[0].arn
}

resource "aws_lambda_permission" "allow_eventbridge" {
  count         = local.github_workflow_poller.enabled? 1 : 0
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.github_workflow_data_poller[0].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.github_workflow_poller[0].arn
}

# VPC Flow Log: configure an IAM role
resource "aws_iam_role" "vpc_flow_log" {
  name               = "AWSVPCFlowLog"
  assume_role_policy = data.aws_iam_policy_document.vpc_flow_log_assume_role_policy.json
}

# VPC Flow Log: assume role policy
data "aws_iam_policy_document" "vpc_flow_log_assume_role_policy" {
  version = "2012-10-17"
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }
  }
}

# VPC Flow Log: publish to CloudWatch
resource "aws_iam_policy" "vpc_flow_log_publish_policy" {
  name   = "AWSVPCFlowLogPublishPolicy"
  policy = data.aws_iam_policy_document.vpc_flow_log_publish_policy.json
}

# Extrapolated from:
# https://docs.aws.amazon.com/vpc/latest/userguide/flow-logs-cwl.html
# tfsec ignore appropriate as wildcard in line with AWS published guidance
# tfsec:ignore:aws-iam-no-policy-wildcards
data "aws_iam_policy_document" "vpc_flow_log_publish_policy" {

  #checkov:skip=CKV_AWS_111: "Ensure IAM policies does not allow write access without constraints - This is limited to the log actions only"
  #checkov:skip=CKV_AWS_356: "Ensure no IAM policies documents allow "*" as a statement's resource for restrictable actions - This is limited to the log actions only"
  #checkov:skip=CKV_AWS_111: "Ensure IAM policies does not allow write access without constraints"

  version = "2012-10-17"

  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy_attachment" "vpc_flow_log_publish_policy" {
  role       = aws_iam_role.vpc_flow_log.id
  policy_arn = aws_iam_policy.vpc_flow_log_publish_policy.arn
}


resource "aws_iam_role" "cortex_xsiam_role" {
  description        = "Role utilised by Palo Alto Cortex XSIAM"
  name_prefix        = "cortex_xsiam"
  assume_role_policy = data.aws_iam_policy_document.cortex_trust_policy.json
  tags               = local.tags
}

resource "aws_iam_policy" "cortex_xsiam_policy" {
  name        = "cortex-user-policy"
  description = "Allows the access to the created SQS queue"
  policy      = data.aws_iam_policy_document.cortex_user_policy.json
}

resource "aws_iam_role_policy_attachment" "cortex_xsiam_role" {
  policy_arn = aws_iam_policy.cortex_xsiam_policy.arn

  role = aws_iam_role.cortex_xsiam_role.name
}

data "aws_iam_policy_document" "cortex_user_policy" {
  statement {
    sid    = "SQSQueueReceiveMessages"
    effect = "Allow"
    actions = [
      "sqs:ChangeMessageVisibility",
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes",
      "sqs:GetQueueUrl",
      "sqs:ListQueues"
    ]
    resources = flatten([
      aws_sqs_queue.mp_cloudtrail_log_queue.arn,
      aws_sqs_queue.mp_modernisation_platform_waf_logs_queue.arn,
      aws_sqs_queue.mp_config_logs_queue.arn,
      aws_sqs_queue.r53_public_dns_logs_queue.arn,
      [for key in aws_sqs_queue.logging : key.arn]
    ])
  }
  statement {
    sid    = "S3GetLogs"
    effect  = "Allow"
    actions = ["s3:GetObject"]
    resources = concat(
      [
        module.s3-bucket-cloudtrail.bucket.arn,
        "${module.s3-bucket-cloudtrail.bucket.arn}/*",
        module.s3_bucket_config_logs.bucket.arn,
        "${module.s3_bucket_config_logs.bucket.arn}/*",
        module.s3_bucket_r53_public_dns_logs.bucket.arn,
        "${module.s3_bucket_r53_public_dns_logs.bucket.arn}/*"
      ],
      [for key in aws_s3_bucket.logging : "${key.arn}/*"]
    )
  }
  statement {
    sid    = "KMSDecryptLogs"
    effect = "Allow"
    actions = [
      "kms:Decrypt",
      "kms:DescribeKey"
    ]
    resources = [for key in aws_kms_key.logging : key.arn]
  }
}

resource "random_uuid" "cortex" {}
data "aws_iam_policy_document" "cortex_trust_policy" {
  statement {
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${aws_ssm_parameter.cortex_account_id.insecure_value}:root"]
      # Palo Alto Cortex AWS Account ID
      # Taken from https://docs-cortex.paloaltonetworks.com/r/Cortex-XDR/Cortex-XDR-Pro-Administrator-Guide/Create-an-Assumed-Role
    }

    actions = ["sts:AssumeRole"]

    condition {
      test     = "StringEquals"
      variable = "sts:ExternalId"
      values   = [sensitive(random_uuid.cortex.result)]
    }
  }
}



# Lambda function to publish metrics for IP usage in subnets across core-vpc accounts and alert when utilisation is high
resource "aws_iam_role" "ip_usage_lambda_exec" {
  name = "IPUsageLambdaRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = {
        Service = "lambda.amazonaws.com"
      },
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_policy_attachment" "ip_usage_lambda_exec" {
  name       = "attach-basic-lambda-exec"
  roles      = [aws_iam_role.ip_usage_lambda_exec.name]
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_policy" "ip_usage_lambda_combined" {
  name        = "IPUsageLambdaCombinedPolicy"
  description = "Combined policy for Lambda: CloudWatch, SNS, STS, and KMS"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = aws_sns_topic.ip_usage_alerts.arn
      },
      {
        Effect = "Allow"
        Action = [
          "sts:AssumeRole"
        ]
        Resource = [
          for acct in local.core_vpc_accounts :
          "arn:aws:iam::${acct}:role/IPUsageMetricsReadRole"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey",
          "kms:GenerateDataKey",
          "kms:Encrypt"
        ]
        Resource = [
          aws_kms_key.ip_usage.arn,
          aws_kms_key.ip_usage_sns_encryption.arn
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ip_usage_lambda_combined" {
  role       = aws_iam_role.ip_usage_lambda_exec.name
  policy_arn = aws_iam_policy.ip_usage_lambda_combined.arn
}

locals {
  core_vpc_accounts = [
    for key, value in local.environment_management.account_ids :
    value if can(regex("^core-vpc-", key))
  ]
}

data "archive_file" "ip_usage_lambda" {
  type        = "zip"
  source_dir  = "${path.module}/lambda/ip_utilisation"
  output_path = "${path.module}/lambda/ip_usage_lambda.zip"
}

resource "aws_lambda_function" "ip_usage" {
  function_name                  = "ip_usage_monitoring"
  role                           = aws_iam_role.ip_usage_lambda_exec.arn
  handler                        = "ip_usage_metrics.lambda_handler"
  runtime                        = "python3.11"
  reserved_concurrent_executions = 1
  timeout                        = 300

  filename         = data.archive_file.ip_usage_lambda.output_path
  source_code_hash = data.archive_file.ip_usage_lambda.output_base64sha256

  kms_key_arn = aws_kms_key.ip_usage.arn

  environment {
    variables = {
      ASSUME_ROLE_NAME = "IPUsageMetricsReadRole"
      TARGET_ACCOUNTS  = join(",", local.core_vpc_accounts)
      AWS_RESERVED_IPS = "5"
      METRIC_NAMESPACE = "Custom/SubnetInfo"
      SNS_TOPIC_ARN    = aws_sns_topic.ip_usage_alerts.arn
    }
  }
  tracing_config {
    mode = "Active"
  }
}
resource "aws_cloudwatch_event_rule" "ip_usage_schedule" {
  name                = "ip-usage-schedule"
  description         = "Trigger IP Usage Lambda every 1 day"
  schedule_expression = "cron(0 10 * *? *)" # run daily at 10:00 UTC
}

resource "aws_cloudwatch_event_target" "ip_usage_lambda_target" {
  rule      = aws_cloudwatch_event_rule.ip_usage_schedule.name
  target_id = "ip-usage-lambda"
  arn       = aws_lambda_function.ip_usage.arn
}

resource "aws_lambda_permission" "allow_cloudwatch_to_invoke" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ip_usage.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.ip_usage_schedule.arn
}

resource "aws_kms_key" "ip_usage" {
  description             = "KMS key for IP Usage Lambda encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow Lambda to decrypt"
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.ip_usage_lambda_exec.arn
        }
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey"
        ]
        Resource = "*"
      }
    ]
  })

  tags = {
    Name = "ip-usage-lambda"
  }
}

resource "aws_kms_alias" "ip_usage" {
  name          = "alias/ip-usage-lambda"
  target_key_id = aws_kms_key.ip_usage.key_id
}

data "aws_iam_policy_document" "ip_usage_kms" {
  statement {
    effect = "Allow"
    actions = [
      "kms:Decrypt",
      "kms:DescribeKey"
    ]
    resources = [aws_kms_key.ip_usage.arn]
  }
}

resource "aws_iam_role_policy" "ip_usage_kms" {
  name   = "ip-usage-kms-decrypt"
  role   = aws_iam_role.ip_usage_lambda_exec.name
  policy = data.aws_iam_policy_document.ip_usage_kms.json
}

resource "aws_kms_key" "ip_usage_sns_encryption" {
  description             = "KMS key for SNS topic encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid    = "Enable IAM User Permissions",
        Effect = "Allow",
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        },
        Action   = "kms:*",
        Resource = "*"
      },
      {
        Sid    = "Allow SNS to use the key",
        Effect = "Allow",
        Principal = {
          Service = "sns.amazonaws.com"
        },
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ],
        Resource = "*"
      }
    ]
  })

  tags = {
    Name = "sns-encryption-key"
  }
}
resource "aws_kms_alias" "ip_usage_sns_topic" {
  name_prefix   = "alias/ip-usage-sns-encryption"
  target_key_id = aws_kms_key.ip_usage_sns_encryption.key_id
}

resource "aws_sns_topic" "ip_usage_alerts" {
  name              = "subnet-utilisation-alerts"
  kms_master_key_id = aws_kms_key.ip_usage_sns_encryption.arn
}

resource "aws_sns_topic_policy" "ip_usage_alerts_policy" {
  arn = aws_sns_topic.ip_usage_alerts.arn

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      # Allow Lambda to publish messages
      {
        Sid    = "AllowLambdaToPublish",
        Effect = "Allow",
        Principal = {
          Service = "lambda.amazonaws.com"
        },
        Action   = "sns:Publish",
        Resource = aws_sns_topic.ip_usage_alerts.arn,
        Condition = {
          ArnEquals = {
            "AWS:SourceArn" = aws_lambda_function.ip_usage.arn
          }
        }
      },
      # Allow topic owner to manage SNS topic
      {
        Sid    = "AllowTopicOwnerToManage",
        Effect = "Allow",
        Principal = {
          AWS = "*"
        },
        Action = [
          "sns:Publish",
          "sns:RemovePermission",
          "sns:SetTopicAttributes",
          "sns:DeleteTopic",
          "sns:ListSubscriptionsByTopic",
          "sns:GetTopicAttributes",
          "sns:AddPermission",
          "sns:Subscribe"
        ],
        Resource = aws_sns_topic.ip_usage_alerts.arn,
        Condition = {
          StringEquals = {
            "AWS:SourceOwner" = local.environment_management.account_ids["core-logging-production"]
          }
        }
      }
    ]
  })
}


data "aws_caller_identity" "modernisation-platform" {
  provider = aws.modernisation-platform
}

data "aws_organizations_organization" "root_account" {}


locals {
  application_name           = "core-logging"
  environment_management     = jsondecode(data.aws_secretsmanager_secret_version.environment_management.secret_string)
  pagerduty_integration_keys = jsondecode(data.aws_secretsmanager_secret_version.pagerduty_integration_keys.secret_string)

  # This takes the name of the Terraform workspace (e.g. core-vpc-production), strips out the application name (e.g. core-vpc), and checks if
  # the string leftover is `-production`, if it isn't (e.g. core-vpc-non-production => -non-production) then it sets the var to false.
  is-production            = substr(terraform.workspace, length(local.application_name), length(terraform.workspace)) == "-production"
  core_logging_bucket_arns = jsondecode(aws_ssm_parameter.core_logging_bucket_arns.insecure_value)

  tags = {
    business-unit = "Platforms"
    service-area  = "Hosting"
    application   = "Modernisation Platform: ${terraform.workspace}"
    is-production = local.is-production
    owner         = "Modernisation Platform: modernisation-platform@digital.justice.gov.uk"
  }
}


module "s3-bucket-cloudtrail" {
  source = "github.com/ministryofjustice/modernisation-platform-terraform-s3-bucket?ref=9facf9fc8f8b8e3f93ffbda822028534b9a75399" # v9.0.0
  providers = {
    aws.bucket-replication = aws.modernisation-platform-eu-west-1
  }
  bucket_policy              = [data.aws_iam_policy_document.cloudtrail_bucket_policy.json]
  bucket_name                = "modernisation-platform-logs-cloudtrail"
  replication_bucket         = "modernisation-platform-logs-cloudtrail-replication"
  suffix_name                = "-cloudtrail"
  custom_kms_key             = aws_kms_key.s3_logging_cloudtrail.arn
  custom_replication_kms_key = aws_kms_key.s3_logging_cloudtrail_eu-west-1_replication.arn
  replication_enabled        = true
  replication_region         = "eu-west-1"
  ownership_controls         = "BucketOwnerEnforced"
  log_bucket                 = module.s3-bucket-cloudtrail-logging.bucket.id
  log_buckets = tomap({
    "log_bucket_name" : module.s3-bucket-cloudtrail-logging.bucket.id,
    "log_bucket_arn" : module.s3-bucket-cloudtrail-logging.bucket.arn,
    "log_bucket_policy" : module.s3-bucket-cloudtrail-logging.bucket_policy.policy,
  })
  log_prefix = ""
  tags       = local.tags
  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "aws:kms"
        kms_master_key_id = aws_kms_key.s3_logging_cloudtrail.arn
      }
    }
  }
}

data "aws_iam_policy_document" "cloudtrail_bucket_policy" {
  statement {
    sid       = "AllowCloudTrailPutObjectWithinOrg"
    effect    = "Allow"
    actions   = ["s3:PutObject"]
    resources = ["${module.s3-bucket-cloudtrail.bucket.arn}/*", module.s3-bucket-cloudtrail.bucket.arn]
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceOrgID"
      values   = [data.aws_organizations_organization.moj_root_account.id]
    }
  }
  statement {
    sid       = "AllowCloudTrailGetBucketAcl"
    effect    = "Allow"
    actions   = ["s3:GetBucketAcl"]
    resources = [module.s3-bucket-cloudtrail.bucket.arn]
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
  }
}


module "s3-bucket-cloudtrail-logging" {
  source = "github.com/ministryofjustice/modernisation-platform-terraform-s3-bucket?ref=9facf9fc8f8b8e3f93ffbda822028534b9a75399" # v9.0.0
  providers = {
    aws.bucket-replication = aws.modernisation-platform-eu-west-1
  }

  bucket_policy              = [data.aws_iam_policy_document.cloudtrail_logging_bucket_policy.json]
  bucket_name                = "modernisation-platform-logs-cloudtrail-logging"
  replication_bucket         = "modernisation-platform-logs-cloudtrail-logging-replication"
  suffix_name                = "-cloudtrail-logging"
  custom_kms_key             = aws_kms_key.s3_logging_cloudtrail.arn
  custom_replication_kms_key = aws_kms_key.s3_logging_cloudtrail_eu-west-1_replication.arn
  ownership_controls         = "BucketOwnerEnforced"

  replication_enabled = true
  replication_region  = "eu-west-1"

  tags = local.tags
  versioning {
    enabled = true
  }
}

data "aws_iam_policy_document" "kms_logging_cloudtrail" {
  # checkov:skip=CKV_AWS_111: "policy is directly related to the resource"
  # checkov:skip=CKV_AWS_356: "policy is directly related to the resource"
  # checkov:skip=CKV_AWS_109: "role is resticted by limited actions in member account"

  statement {
    sid    = "Allow management access of the key to the logging account"
    effect = "Allow"
    actions = [
      "kms:*"
    ]
    resources = [
      "*"
    ]
    principals {
      type = "AWS"
      identifiers = [
        data.aws_caller_identity.current.account_id
      ]
    }
  }

  statement {
    sid    = "Enable decrypt access to accounts within the organisation"
    effect