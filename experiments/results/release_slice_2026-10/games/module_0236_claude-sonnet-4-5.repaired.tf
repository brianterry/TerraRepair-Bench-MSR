data "aws_caller_identity" "mod-platform" {
  provider = aws.modernisation-platform
}

data "aws_kms_alias" "environment_management" {
  provider = aws.modernisation-platform
  name     = "alias/environment-management-multi-region"
}

module "s3-bucket-athena" {
  source = "github.com/ministryofjustice/modernisation-platform-terraform-s3-bucket?ref=9facf9fc8f8b8e3f93ffbda822028534b9a75399"
  providers = {
    aws.bucket-replication = aws.modernisation-platform-eu-west-1
  }
  bucket_policy       = [data.aws_iam_policy_document.athena_bucket_policy.json]
  bucket_name         = "athena-cloudtrail-query"
  custom_kms_key      = aws_kms_key.s3_logging_cloudtrail.arn
  replication_enabled = false
  log_bucket          = module.s3-bucket-cloudtrail-logging.bucket.id
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
        encryption_option = "SSE_S3"
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
        Resource = "arn:aws:ssm:eu-west-2:${data.aws_caller_identity.current.account_id}:parameter/environment_management_arn"
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
  tracing_config {
    mode = "Active"
  }
  environment {
    variables = {
      mod_account = data.aws_caller_identity.mod-platform.account_id
    }
  }
}

resource "aws_cloudwatch_event_rule" "every_day" {
  name                = "run-daily"
  description         = "Runs daily at 12:15"
  schedule_expression = "cron(15 0 * * ? *)"
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

terraform {
  backend "s3" {
    acl                  = "bucket-owner-full-control"
    bucket               = "modernisation-platform-terraform-state"
    encrypt              = true
    key                  = "terraform.tfstate"
    region               = "eu-west-2"
    use_lockfile         = true
    workspace_key_prefix = "environments/accounts/core-logging"
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
    schedule_expression = "cron(0/15 * * * ? *)"
    log_retention_days  = 90
  }
}

resource "aws_cloudwatch_log_group" "github_workflow_data" {
  count             = local.github_workflow_poller.enabled ? 1 : 0
  name              = "modernisation-platform-workflow-data"
  retention_in_days = local.github_workflow_poller.log_retention_days
  kms_key_id        = aws_kms_key.athena_logging.arn

  tags = merge(
    local.tags,
    {
      Name = "modernisation-platform-workflow-data"
    }
  )
}

resource "aws_cloudwatch_log_group" "github_workflow_poller_lambda" {
  count             = local.github_workflow_poller.enabled ? 1 : 0
  name              = "/aws/lambda/github-workflow-data-poller"
  retention_in_days = local.github_workflow_poller.log_retention_days
  kms_key_id        = aws_kms_key.athena_logging.arn

  tags = merge(
    local.tags,
    {
      Name = "github-workflow-data-poller-logs"
    }
  )
}

resource "aws_iam_role" "github_workflow_poller_lambda" {
  count = local.github_workflow_poller.enabled ? 1 : 0
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
  count = local.github_workflow_poller.enabled ? 1 : 0
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
  count       = local.github_workflow_poller.enabled ? 1 : 0
  type        = "zip"
  source_file = "${path.module}/lambda/github_workflow_data_poller/github_workflow_data_poller.py"
  output_path = "${path.module}/lambda/github_workflow_data_poller/lambda.zip"
}

resource "aws_lambda_function" "github_workflow_data_poller" {
  count                          = local.github_workflow_poller.enabled ? 1 : 0
  filename                       = data.archive_file.github_workflow_poller_lambda[0].output_path
  function_name                  = "github-workflow-data-poller"
  role                           = aws_iam_role.github_workflow_poller_lambda[0].arn
  handler                        = "github_workflow_data_poller.lambda_handler"
  source_code_hash               = data.archive_file.github_workflow_poller_lambda[0].output_base64sha256
  runtime                        = "python3.12"
  timeout                        = 300
  description                    = "Polls GitHub Actions workflow data and writes to CloudWatch Logs"
  reserved_concurrent_executions = 10

  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      GITHUB_OWNER           = local.github_workflow_poller.github_owner
      GITHUB_REPO            = local.github_workflow_poller.github_repo
      LOOKBACK_HOURS         = local.github_workflow_poller.lookback_hours
      WORKFLOW_RUN_LOG_GROUP = aws_cloudwatch_log_group.github_workflow_data[0].name
      GITHUB_TOKEN           = ""
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
}

resource "aws_cloudwatch_event_rule" "github_workflow_poller" {
  count               = local.github_workflow_poller.enabled ? 1 : 0
  name                = "github-workflow-data-poller"
  description         = "Trigger GitHub workflow data poller"
  schedule_expression = local.github_workflow_poller.schedule_expression

  tags = local.tags
}

resource "aws_cloudwatch_event_target" "github_workflow_poller" {
  count = local.github_workflow_poller.enabled ? 1 : 0
  rule  = aws_cloudwatch_event_rule.github_workflow_poller[0].name
  arn   = aws_lambda_function.github_workflow_data_poller[0].arn
}

resource "aws_lambda_permission" "allow_eventbridge" {
  count         = local.github_workflow_poller.enabled ? 1 : 0
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.github_workflow_data_poller[0].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.github_workflow_poller[0].arn
}

resource "aws_iam_role" "vpc_flow_log" {
  name               = "AWSVPCFlowLog"
  assume_role_policy = data.aws_iam_policy_document.vpc_flow_log_assume_role_policy.json
}

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

resource "aws_iam_policy" "vpc_flow_log_publish_policy" {
  name   = "AWSVPCFlowLogPublishPolicy"
  policy = data.aws_iam_policy_document.vpc_flow_log_publish_policy.json
}

data "aws_iam_policy_document" "vpc_flow_log_publish_policy" {

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
    sid     = "S3GetLogs"
    effect  = "Allow"
    actions = ["s3:GetObject"]
    resources = concat(
      [
        module.s3-bucket-cloudtrail.bucket.arn,
        "${module.s3-bucket-cloudtrail.bucket.arn}/*",
        module.s3-bucket-modernisation-platform-waf-logs.bucket.arn,
        "${module.s3-bucket-modernisation-platform-waf-logs.bucket.arn}/*",
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
    }

    actions = ["sts:AssumeRole"]

    condition {
      test     = "StringEquals"
      variable = "sts:ExternalId"
      values   = [sensitive(random_uuid.cortex.result)]
    }
  }
}

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

  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      ASSUME_ROLE_NAME = "IPUsageMetricsReadRole"
      TARGET_ACCOUNTS  = join(",", local.core_vpc_accounts)
      AWS_RESERVED_IPS = "5"
      METRIC_NAMESPACE = "Custom/SubnetInfo"
      SNS_TOPIC_ARN    = aws_sns_topic.ip_usage_alerts.arn
    }
  }
}
resource "aws_cloudwatch_event_rule" "ip_usage_schedule" {
  name                = "ip-usage-schedule"
  description         = "Trigger IP Usage Lambda every 1 day"
  schedule_expression = "cron(0 10 * * ? *)"
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
  source = "github.com/ministryofjustice/modernisation-platform-terraform-s3-bucket?ref=9facf9fc8f8b8e3f93ffbda822028534b9a75399"
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
  source = "github.com/ministryofjustice/modernisation-platform-terraform-s3-bucket?ref=9facf9fc8f8b8e3f93ffbda822028534b9a75399"
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
}

data "aws_iam_policy_document" "cloudtrail_logging_bucket_policy" {
  statement {
    sid       = "AllowS3ServerAccessLoggingPutObjectFromSourceBucketWithinAccount"
    effect    = "Allow"
    actions   = ["s3:PutObject"]
    resources = ["${module.s3-bucket-cloudtrail-logging.bucket.arn}/*"]
    principals {
      type        = "Service"
      identifiers = ["logging.s3.amazonaws.com"]
    }
    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [module.s3-bucket-cloudtrail.bucket.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_kms_key" "s3_logging_cloudtrail" {
  description             = "s3-logging-cloudtrail"
  policy                  = data.aws_iam_policy_document.kms_logging_cloudtrail.json
  enable_key_rotation     = true
  deletion_window_in_days = 30
}

resource "aws_kms_alias" "s3_logging_cloudtrail" {
  name          = "alias/s3-logging-cloudtrail"
  target_key_id = aws_kms_key.s3_logging_cloudtrail.id
}

data "aws_iam_policy_document" "kms_logging_cloudtrail" {

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
    effect = "Allow"
    actions = [
      "kms:Describe*",
      "kms:Decrypt*"
    ]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:PrincipalOrgID"
      values = [
        data.aws_organizations_organization.moj_root_account.id
      ]
    }
  }

  statement {
    sid    = "Allow use of the key including encryption"
    effect = "Allow"
    actions = [
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:Encrypt*",
      "kms:Describe*",
      "kms:Decrypt*"
    ]
    resources = ["*"]
    principals {
      type        = "Service"
      identifiers = ["logging.s3.amazonaws.com", "cloudtrail.amazonaws.com", "logs.amazonaws.com"]
    }
  }

  statement {
    sid    = "Allow use of the key by SQS"
    effect = "Allow"
    actions = [
      "kms:Describe*",
      "kms:Decrypt*"
    ]
    resources = [aws_sqs_queue.mp_cloudtrail_log_queue.arn]
    principals {
      type        = "Service"
      identifiers = ["sqs.amazonaws.com"]
    }
  }

  statement {
    sid    = "Allow use of the key by the ModernisationPlatformAccess role in all MP accounts"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    actions = [
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:Encrypt*",
      "kms:Describe*",
      "kms:Decrypt*"
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:PrincipalOrgID"
      values   = [data.aws_organizations_organization.moj_root_account.id]
    }
    condition {
      test     = "StringLike"
      variable = "aws:PrincipalArn"
      values   = ["arn:aws:iam::*:role/ModernisationPlatformAccess"]
    }
  }

  statement {
    sid    = "Allow key decryption to STS bucket replication roles"
    effect = "Allow"
    actions = [
      "kms:Decrypt*"
    ]
    resources = ["*"]
    principals {
      type = "AWS"
      identifiers = [
        "arn:aws:sts::${data.aws_caller_identity.current.account_id}:assumed-role/AWSS3BucketReplication-cloudtrail/s3-replication",
        "arn:aws:sts::${data.aws_caller_identity.current.account_id}:assumed-role/AWSS3BucketReplication-cloudtrail-logging/s3-replication",
      ]
    }
  }
}

resource "aws_kms_key" "s3_logging_cloudtrail_eu-west-1_replication" {
  provider = aws.modernisation-platform-eu-west-1

  description             = "s3-logging-cloudtrail-eu-west-1-replication"
  policy                  = data.aws_iam_policy_document.kms_logging_cloudtrail_replication.json
  enable_key_rotation     = true
  deletion_window_in_days = 30
  tags                    = { Name = "${local.application_name}-s3-logging-cloudtrail-kms" }
}

resource "aws_kms_alias" "s3_logging_cloudtrail_eu-west-1_replication" {
  provider = aws.modernisation-platform-eu-west-1

  name          = "alias/s3-logging-cloudtrail-eu-west-1-replication"
  target_key_id = aws_kms_key.s3_logging_cloudtrail_eu-west-1_replication.id
}

data "aws_iam_policy_document" "kms_logging_cloudtrail_replication" {
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
    sid    = "Allow key decryption to STS bucket replication roles"
    effect = "Allow"
    actions = [
      "kms:ReEncrypt*",
      "kms:Encrypt*",
      "kms:Describe*"
    ]
    resources = ["*"]
    principals {
      type = "AWS"
      identifiers = [
        "arn:aws:sts::${data.aws_caller_identity.current.account_id}:assumed-role/AWSS3BucketReplication-cloudtrail/s3-replication",
        "arn:aws:sts::${data.aws_caller_identity.current.account_id}:assumed-role/AWSS3BucketReplication-cloudtrail-logging/s3-replication",
      ]
    }
  }
}

resource "aws_sqs_queue" "mp_cloudtrail_log_queue" {
  name                       = "mp_cloudtrail_log_queue"
  sqs_managed_sse_enabled    = true
  delay_seconds              = 0
  max_message_size           = 262144
  message_retention_seconds  = 345600
  visibility_timeout_seconds = 30
}

resource "aws_sqs_queue_policy" "queue_policy" {
  queue_url = aws_sqs_queue.mp_cloudtrail_log_queue.id
  policy    = data.aws_iam_policy_document.queue_policy_document.json
}

data "aws_iam_policy_document" "queue_policy_document" {
  statement {
    sid    = "AllowSendMessage"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["s3.amazonaws.com"]
    }
    actions = ["sqs:SendMessage"]
    resources = [
      aws_sqs_queue.mp_cloudtrail_log_queue.arn
    ]
    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [module.s3-bucket-cloudtrail.bucket.arn]
    }
  }
}

resource "aws_s3_bucket_notification" "logging_bucket_notification" {
  bucket = module.s3-bucket-cloudtrail.bucket.id
  queue {
    queue_arn = aws_sqs_queue.mp_cloudtrail_log_queue.arn
    events    = ["s3:ObjectCreated:*"]
  }
}

module "s3_bucket_config_logs" {
  source = "github.com/ministryofjustice/modernisation-platform-terraform-s3-bucket?ref=9facf9fc8f8b8e3f93ffbda822028534b9a75399"

  providers = {
    aws.bucket-replication = aws.modernisation-platform-eu-west-1
  }
  bucket_policy              = [data.aws_iam_policy_document.config_bucket_policy.json]
  bucket_name                = "modernisation-platform-logs-config"
  replication_bucket         = "modernisation-platform-logs-config-replication"
  suffix_name                = "-config"
  custom_kms_key             = aws_kms_key.config_logs.arn
  custom_replication_kms_key = aws_kms_key.config_logs_replication.arn
  replication_enabled        = true
  replication_region         = "eu-west-1"
  versioning_enabled         = true

  lifecycle_rule = [
    {
      id      = "main"
      enabled = "Enabled"
      prefix  = ""
      tags    = {}
      transition = [
        {
          days          = 90
          storage_class = "STANDARD_IA"
          }, {
          days          = 365
          storage_class = "GLACIER"
        }
      ]
      expiration = {
        days = 730
      }
      noncurrent_version_transition = [
        {
          days          = 90
          storage_class = "STANDARD_IA"
          }, {
          days          = 365
          storage_class = "GLACIER"
        }
      ]
      noncurrent_version_expiration = {
        days = 730
      }
    }
  ]

  tags = local.tags
}

data "aws_iam_policy_document" "config_bucket_policy" {
  statement {
    sid    = "AllowAWSConfigPutObject"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }
    actions = ["s3:PutObject"]
    resources = [
      "${module.s3_bucket_config_logs.bucket.arn}/*"
    ]
    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceOrgID"
      values   = [data.aws_organizations_organization.moj_root_account.id]
    }
  }

  statement {
    sid    = "AllowGetBucketAcl"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }
    actions   = ["s3:GetBucketAcl"]
    resources = [module.s3_bucket_config_logs.bucket.arn]
  }

  statement {
    sid    = "AllowAWSConfigListObject"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    actions   = ["s3:ListBucket"]
    resources = [module.s3_bucket_config_logs.bucket.arn]
    condition {
      test     = "StringEquals"
      variable = "aws:PrincipalOrgID"
      values   = [data.aws_organizations_organization.moj_root_account.id]
    }
  }
}

resource "aws_kms_key" "config_logs" {
  description             = "KMS key for encrypting AWS Config logs in central bucket"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  policy                  = data.aws_iam_policy_document.kms_config_logs.json
  tags                    = { Name = "modernisation-platform-config-logs-kms" }
}

resource "aws_kms_alias" "config_logs" {
  name          = "alias/config-logs-kms"
  target_key_id = aws_kms_key.config_logs.key_id
}

data "aws_iam_policy_document" "kms_config_logs" {
  statement {
    sid       = "AllowRootAccess"
    effect    = "Allow"
    actions   = ["kms:*"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = [data.aws_caller_identity.current.account_id]
    }
  }

  statement {
    sid    = "AllowUseByAWSConfig"
    effect = "Allow"
    actions = [
      "kms:Decrypt",
      "kms:Encrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:Describe*"
    ]
    resources = ["*"]
    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceOrgID"
      values   = [data.aws_organizations_organization.moj_root_account.id]
    }
  }

  statement {
    sid       = "AllowReplicationAccess"
    effect    = "Allow"
    actions   = ["kms:Decrypt"]
    resources = ["*"]
    principals {
      type = "AWS"
      identifiers = [
        "arn:aws:sts::${data.aws_caller_identity.current.account_id}:assumed-role/AWSS3BucketReplication-config/s3-replication"
      ]
    }
  }
}

resource "aws_kms_key" "config_logs_replication" {
  provider                = aws.modernisation-platform-eu-west-1
  description             = "KMS key for replicated AWS Config logs in eu-west-1"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  policy                  = data.aws_iam_policy_document.kms_config_logs_replication.json
  tags                    = { Name = "modernisation-platform-config-logs-kms-replication" }
}

resource "aws_kms_alias" "config_logs_replication" {
  provider      = aws.modernisation-platform-eu-west-1
  name          = "alias/config-logs-kms-replication"
  target_key_id = aws_kms_key.config_logs_replication.key_id
}

data "aws_iam_policy_document" "kms_config_logs_replication" {
  statement {
    sid       = "AllowRootAccess"
    effect    = "Allow"
    actions   = ["kms:*"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = [data.aws_caller_identity.current.account_id]
    }
  }

  statement {
    sid       = "AllowReplicationAccess"
    effect    = "Allow"
    actions   = ["kms:ReEncrypt*", "kms:Encrypt", "kms:Describe"]
    resources = ["*"]
    principals {
      type = "AWS"
      identifiers = [
        "arn:aws:sts::${data.aws_caller_identity.current.account_id}:assumed-role/AWSS3BucketReplication-config/s3-replication"
      ]
    }
  }
}

resource "aws_sqs_queue" "mp_config_logs_queue" {
  name                       = "mp_config_logs_queue"
  sqs_managed_sse_enabled    = true
  delay_seconds              = 0
  max_message_size           = 262144
  message_retention_seconds  = 345600
  visibility_timeout_seconds = 30
}

resource "aws_sqs_queue_policy" "config_logs_queue_policy" {
  queue_url = aws_sqs_queue.mp_config_logs_queue.id
  policy    = data.aws_iam_policy_document.config_logs_queue_policy_document.json
}

data "aws_iam_policy_document" "config_logs_queue_policy_document" {
  statement {
    sid    = "AllowSendMessage"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["s3.amazonaws.com"]
    }
    actions = ["sqs:SendMessage"]
    resources = [
      aws_sqs_queue.mp_config_logs_queue.arn
    ]
    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [module.s3_bucket_config_logs.bucket.arn]
    }
  }
}

resource "aws_s3_bucket_notification" "waf_logs_bucket_notification" {
  bucket = module.s3_bucket_config_logs.bucket.id
  queue {
    queue_arn = aws_sqs_queue.mp_config_logs_queue.arn
    events    = ["s3:ObjectCreated:*"]
  }
}

resource "aws_cloudwatch_log_destination" "r53_public_dns_logs" {
  provider   = aws.aws-us-east-1
  name       = "r53-public-dns-logs-destination"
  role_arn   = aws_iam_role.cwl_to_firehose_r53_public_dns.arn
  target_arn = aws_kinesis_firehose_delivery_stream.r53_public_dns_logs_to_s3.arn

  depends_on = [
    aws_kinesis_firehose_delivery_stream.r53_public_dns_logs_to_s3,
    aws_iam_role_policy.cwl_to_firehose_policy_r53_public_dns
  ]
}

resource "aws_cloudwatch_log_destination_policy" "r53_public_dns_logs" {
  provider         = aws.aws-us-east-1
  destination_name = aws_cloudwatch_log_destination.r53_public_dns_logs.name
  access_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect    = "Allow",
      Principal = "*",
      Action    = "logs:PutSubscriptionFilter",
      Resource  = aws_cloudwatch_log_destination.r53_public_dns_logs.arn,
      Condition = {
        StringEquals = {
          "aws:PrincipalOrgID" = data.aws_organizations_organization.current.id
        }
      }
    }]
  })
}

resource "aws_iam_role" "cwl_to_firehose_r53_public_dns" {
  provider = aws.aws-us-east-1
  name     = "CWLtoFirehoseRoleR53PublicDNS"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement : [{
      Effect = "Allow",
      Principal : {
        Service = "logs.us-east-1.amazonaws.com"
      },
      Action : "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "cwl_to_firehose_policy_r53_public_dns" {
  provider = aws.aws-us-east-1
  name     = "Permissions-Policy-For-CWL-R53-Public-DNS"
  role     = aws_iam_role.cwl_to_firehose_r53_public_dns.name

  policy = jsonencode({
    Version = "2012-10-17",
    Statement : [{
      Effect   = "Allow",
      Action   = ["firehose:*"],
      Resource = [aws_kinesis_firehose_delivery_stream.r53_public_dns_logs_to_s3.arn]
    }]
  })
}

resource "aws_iam_role" "firehose_to_s3_r53_public_dns" {
  provider = aws.aws-us-east-1
  name     = "firehose_to_s3_r53_public_dns"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = [
            "firehose.amazonaws.com",
            "logs.amazonaws.com"
          ]
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "firehose_to_s3_r53_public_dns_policy" {
  provider = aws.aws-us-east-1
  role     = aws_iam_role.firehose_to_s3_r53_public_dns.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:PutObjectAcl"
        ]
        Resource = "${module.s3_bucket_r53_public_dns_logs.bucket.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = aws_kms_key.r53_public_dns_logs.arn
      },
      {
        Effect = "Allow"
        Action = [
          "firehose:PutRecord",
          "firehose:PutRecordBatch"
        ]
        Resource = "arn:aws:firehose:us-east-1:${data.aws_caller_identity.current.account_id}:deliverystream/r53-public-dns-logs-to-s3"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:us-east-1:${data.aws_caller_identity.current.account_id}:log-group:/aws/kinesisfirehose/r53-public-dns-logs-to-s3:*"
      }
    ]
  })
}

resource "aws_kinesis_firehose_delivery_stream" "r53_public_dns_logs_to_s3" {
  provider    = aws.aws-us-east-1
  name        = "r53-public-dns-logs-to-s3"
  destination = "extended_s3"

  extended_s3_configuration {
    role_arn            = aws_iam_role.firehose_to_s3_r53_public_dns.arn
    bucket_arn          = module.s3_bucket_r53_public_dns_logs.bucket.arn
    prefix              = "r53-public-dns-logs/"
    error_output_prefix = "r53-public-dns-logs-error/"
    buffering_interval  = 300
    buffering_size      = 5
    compression_format  = "UNCOMPRESSED"
    kms_key_arn         = aws_kms_key.r53_public_dns_logs.arn
  }

  depends_on = [aws_iam_role_policy.firehose_to_s3_r53_public_dns_policy]
}

resource "aws_kms_key" "r53_public_dns_logs" {
  description             = "KMS key for encrypting Route 53 public DNS logs"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  policy                  = data.aws_iam_policy_document.kms_r53_public_dns_logs.json
  tags                    = { Name = "modernisation-platform-r53-public-dns-logs-kms" }
}

resource "aws_kms_alias" "r53_public_dns_logs" {
  name          = "alias/r53-public-dns-logs-kms"
  target_key_id = aws_kms_key.r53_public_dns_logs.key_id
}

data "aws_iam_policy_document" "kms_r53_public_dns_logs" {

  statement {
    sid       = "AllowKeyAdmin"
    effect    = "Allow"
    actions   = ["kms:*"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = [data.aws_caller_identity.current.account_id]
    }
  }

  statement {
    sid    = "AllowFirehoseAndLogsEncrypt"
    effect = "Allow"
    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:GenerateDataKey*",
      "kms:DescribeKey"
    ]
    resources = ["*"]
    principals {
      type = "Service"
      identifiers = [
        "firehose.amazonaws.com",
        "logs.${data.aws_region.current.region}.amazonaws.com"
      ]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.environment_management.account_ids["core-network-services-production"]]
    }
  }

  statement {
    sid    = "AllowCortexXsiamDecrypt"
    effect = "Allow"
    actions = [
      "kms:Decrypt",
      "kms:DescribeKey"
    ]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.cortex_xsiam_role.arn]
    }
  }

  statement {
    sid    = "AllowSQSDecrypt"
    effect = "Allow"
    actions = [
      "kms:Decrypt",
      "kms:DescribeKey"
    ]
    resources = ["*"]
    principals {
      type        = "Service"
      identifiers = ["sqs.amazonaws.com"]
    }
  }

  statement {
    sid    = "AllowS3Replication"
    effect = "Allow"
    actions = [
      "kms:Decrypt",
      "kms:Encrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey"
    ]
    resources = ["*"]
    principals {
      type = "AWS"
      identifiers = [
        format(
          "arn:aws:sts::%s:assumed-role/AWSS3BucketReplication-r53-public-dns-logs/s3-replication",
          data.aws_caller_identity.current.account_id
        )
      ]
    }
  }
}

resource "aws_kms_key" "r53_public_dns_logs_replication" {
  provider                = aws.modernisation-platform-eu-west-1
  description             = "KMS key for replicated Route 53 public DNS logs in eu-west-1"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  policy                  = data.aws_iam_policy_document.kms_r53_public_dns_logs_replication.json
  tags                    = { Name = "modernisation-platform-r53-public-dns-logs-kms-replication" }
}

resource "aws_kms_alias" "r53_public_dns_logs_replication" {
  provider      = aws.modernisation-platform-eu-west-1
  name          = "alias/r53-public-dns-logs-kms-replication"
  target_key_id = aws_kms_key.r53_public_dns_logs_replication.id
}

data "aws_iam_policy_document" "kms_r53_public_dns_logs_replication" {
  statement {
    sid       = "AllowRootAccess"
    effect    = "Allow"
    actions   = ["kms:*"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = [data.aws_caller_identity.current.account_id]
    }
  }

  statement {
    sid       = "AllowReplicationAccess"
    effect    = "Allow"
    actions   = ["kms:ReEncrypt*", "kms:Encrypt", "kms:Describe"]
    resources = ["*"]
    principals {
      type = "AWS"
      identifiers = [
        "arn:aws:sts::${data.aws_caller_identity.current.account_id}:assumed-role/AWSS3BucketReplication-r53-public-dns-logs/s3-replication"
      ]
    }
  }
}

module "s3_bucket_r53_public_dns_logs" {
  source = "github.com/ministryofjustice/modernisation-platform-terraform-s3-bucket?ref=9facf9fc8f8b8e3f93ffbda822028534b9a75399"

  providers = {
    aws.bucket-replication = aws.modernisation-platform-eu-west-1
  }
  bucket_policy              = [data.aws_iam_policy_document.r53_public_dns_logs_bucket_policy.json]
  bucket_name                = "modernisation-platform-logs-r53-public-dns-logs"
  replication_bucket         = "modernisation-platform-logs-r53-public-dns-logs-replication"
  suffix_name                = "-r53-public-dns-logs"
  custom_kms_key             = aws_kms_key.r53_public_dns_logs.arn
  custom_replication_kms_key = aws_kms_key.r53_public_dns_logs_replication.arn
  replication_enabled        = true
  replication_region         = "eu-west-1"
  versioning_enabled         = true

  lifecycle_rule = [
    {
      id      = "main"
      enabled = "Enabled"
      prefix  = ""
      tags    = {}
      transition = [
        {
          days          = 90
          storage_class = "STANDARD_IA"
          }, {
          days          = 365
          storage_class = "GLACIER"
        }
      ]
      expiration = {
        days = 730
      }
      noncurrent_version_transition = [
        {
          days          = 90
          storage_class = "STANDARD_IA"
          }, {
          days          = 365
          storage_class = "GLACIER"
        }
      ]
      noncurrent_version_expiration = {
        days = 730
      }
    }
  ]

  tags = local.tags
}

data "aws_iam_policy_document" "r53_public_dns_logs_bucket_policy" {
  statement {
    sid       = "AllowFirehosePut"
    effect    = "Allow"
    actions   = ["s3:PutObject"]
    resources = ["arn:aws:s3:::modernisation-platform-logs-r53-public-dns-logs/*"]
    principals {
      type        = "Service"
      identifiers = ["firehose.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.environment_management.account_ids["core-network-services-production"]]
    }
  }

  statement {
    sid       = "DenyUnencryptedObjectUploads"
    effect    = "Deny"
    actions   = ["s3:PutObject"]
    resources = ["arn:aws:s3:::modernisation-platform-logs-r53-public-dns-logs/*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Null"
      variable = "s3:x-amz-server-side-encryption"
      values   = ["true"]
    }
  }

  statement {
    sid       = "AllowListBucket"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = ["arn:aws:s3:::modernisation-platform-logs-r53-public-dns-logs"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.environment_management.account_ids["core-network-services-production"]]
    }
  }
}

resource "aws_sqs_queue" "r53_public_dns_logs_queue" {
  name                       = "r53_public_dns_logs_queue"
  sqs_managed_sse_enabled    = true
  delay_seconds              = 0
  max_message_size           = 262144
  message_retention_seconds  = 345600
  visibility_timeout_seconds = 30
  tags = {
    Name = "r53_public_dns_logs_queue"
  }
}

resource "aws_sqs_queue_policy" "r53_public_dns_logs_queue_policy" {
  queue_url = aws_sqs_queue.r53_public_dns_logs_queue.id
  policy    = data.aws_iam_policy_document.r53_public_dns_logs_queue_policy_document.json
}

data "aws_iam_policy_document" "r53_public_dns_logs_queue_policy_document" {
  statement {
    sid    = "AllowSendMessage"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["s3.amazonaws.com"]
    }
    actions = ["sqs:SendMessage"]
    resources = [
      aws_sqs_queue.r53_public_dns_logs_queue.arn
    ]
    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [module.s3_bucket_r53_public_dns_logs.bucket.arn]
    }
  }
}

resource "aws_s3_bucket_notification" "r53_public_dns_logs_bucket_notification" {
  bucket = module.s3_bucket_r53_public_dns_logs.bucket.id
  queue {
    queue_arn = aws_sqs_queue.r53_public_dns_logs_queue.arn
    events    = ["s3:ObjectCreated:*"]
  }
}

locals {
  resolver_query_log_config_names = toset(["core-logging-rlq-cloudwatch", "core-logging-rlq-s3"])
  vpc_ids                         = { for key, value in module.vpc : key => value["vpc_id"] if key == "live_data" }
  rlq_ids                         = { for name, config in data.aws_route53_resolver_query_log_config.core_logging : name => config.id }
  vpc_rlq_associations = merge([
    for vpc_key, vpc_id in local.vpc_ids : {
      for rlq_name, rlq_id in local.rlq_ids :
      "${vpc_key}_${rlq_name}" => {
        vpc_id = vpc_id
        rlq_id = rlq_id
      }
    }
  ]...)
}

data "aws_route53_resolver_query_log_config" "core_logging" {
  for_each = local.resolver_query_log_config_names
  filter {
    name   = "Name"
    values = [each.value]
  }
}
resource "aws_route53_resolver_query_log_config" "s3" {
  name            = format("%s-rlq-s3", local.application_name)
  destination_arn = aws_s3_bucket.logging["r53-resolver-logs"].arn
  tags            = local.tags
}

resource "aws_route53_resolver_query_log_config" "s3_eu_west_1" {
  provider        = aws.modernisation-platform-eu-west-1
  name            = format("%s-rlq-s3-%s", local.application_name, "eu-west-1")
  destination_arn = aws_s3_bucket.logging["r53-resolver-logs"].arn
  tags            = local.tags
}

resource "aws_route53_resolver_query_log_config" "cloudwatch" {
  name            = format("%s-rlq-cloudwatch", local.application_name)
  destination_arn = aws_cloudwatch_log_group.r53_resolver_logs.arn
  tags            = local.tags
}

resource "aws_cloudwatch_log_group" "r53_resolver_logs" {
  kms_key_id        = aws_kms_key.r53_resolver_logs.arn
  name_prefix       = "r53-resolver-logs"
  retention_in_days = 365
  tags              = local.tags
}

resource "aws_route53_resolver_query_log_config_association" "core_logging" {
  for_each                     = local.is-production ? local.vpc_rlq_associations : {}
  resolver_query_log_config_id = each.value.rlq_id
  resource_id                  = each.value.vpc_id
}

resource "aws_cloudwatch_log_metric_filter" "r53_dns_firewall_metric_filter" {
  name           = "r53-dns-firewall-matches"
  log_group_name = aws_cloudwatch_log_group.r53_resolver_logs.name

  pattern = "{ ($.firewall_rule_action = \"BLOCK\" || $.firewall_rule_action = \"ALERT\") }"
  metric_transformation {
    name      = "r53-dns-firewall-matches"
    namespace = "R53DNSFirewall"
    value     = "1"
  }
}

resource "aws_cloudwatch_metric_alarm" "r53_dns_firewall_alarm" {
  alarm_name          = "r53-dns-firewall-matches"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "1"
  metric_name         = aws_cloudwatch_log_metric_filter.r53_dns_firewall_metric_filter.metric_transformation[0].name
  namespace           = aws_cloudwatch_log_metric_filter.r53_dns_firewall_metric_filter.metric_transformation[0].namespace
  period              = "60"
  statistic           = "Sum"
  threshold           = "1"
  alarm_actions       = [aws_sns_topic.r53_dns_firewall.arn]
  tags                = local.tags
}

resource "aws_sns_topic" "r53_dns_firewall" {
  name              = "r53-dns-firewall-sns-topic"
  kms_master_key_id = aws_kms_key.r53_dns_firewall.key_id
  tags              = local.tags
}

resource "aws_kms_key" "r53_dns_firewall" {
  description         = "KMS key for DNS Firewall SNS Topic Encryption"
  enable_key_rotation = true
  policy              = data.aws_iam_policy_document.r53_dns_firewall_kms_policy.json
  tags                = merge(local.tags, { Name = "${local.application_name}-r53-kms" })
}

resource "aws_kms_alias" "r53_dns_firewall" {
  name_prefix   = "alias/r53-dns-firewall-sns-encryption"
  target_key_id = aws_kms_key.r53_dns_firewall.key_id
}

data "aws_iam_policy_document" "r53_dns_firewall_kms_policy" {
  statement {
    sid    = "Allow SNS/Cloudwatch services to use the KMS key"
    effect = "Allow"
    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey"
    ]
    resources = [
      "*"
    ]
    principals {
      type        = "Service"
      identifiers = ["sns.amazonaws.com", "cloudwatch.amazonaws.com", "logs.amazonaws.com"]
    }
  }

  statement {
    sid    = "Allow account to manage key"
    effect = "Allow"
    actions = [
      "kms:*"
    ]
    resources = [
      "*"
    ]
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }
}
module "pagerduty_r53_dns_firewall" {
  depends_on                = [aws_sns_topic.r53_dns_firewall]
  source                    = "github.com/ministryofjustice/modernisation-platform-terraform-pagerduty-integration?ref=d88bd90d490268896670a898edfaba24bba2f8ab"
  sns_topics                = [aws_sns_topic.r53_dns_firewall.name]
  pagerduty_integration_key = local.pagerduty_integration_keys["core_alerts_cloudwatch"]
}

resource "aws_kms_key" "r53_resolver_logs" {
  description         = "KMS key used to encrypt R53 Resolver Logs CloudWatch log group"
  enable_key_rotation = true
  multi_region        = true
  policy              = data.aws_iam_policy_document.r53_resolver_logs_kms.json
  tags                = local.tags
}

data "aws_iam_policy_document" "r53_resolver_logs_kms" {
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
    sid    = "Allow AWS Log service to use key"
    effect = "Allow"
    actions = [
      "kms:Encrypt*",
      "kms:Decrypt*",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:Describe*"
    ]
    resources = [
      "*"
    ]
    principals {
      type = "Service"
      identifiers = [
        "logs.amazonaws.com"
      ]
    }
  }
}

locals {
  resolver_query_log_configs = {
    s3         = aws_route53_resolver_query_log_config.s3.arn
    cloudwatch = aws_route53_resolver_query_log_config.cloudwatch.arn
  }
}

resource "aws_ram_resource_share" "resolver_query_share" {
  allow_external_principals = false
  name                      = format("%s-resolver-log-query-share", local.application_name)
  tags                      = local.tags
}

resource "aws_ram_resource_association" "resolver_query_share" {
  for_each           = local.resolver_query_log_configs
  resource_arn       = each.value
  resource_share_arn = aws_ram_resource_share.resolver_query_share.id
}

resource "aws_ram_principal_association" "resolver_query_share" {
  principal          = replace("${data.aws_organizations_organization.root_account.arn}/${local.environment_management.modernisation_platform_organisation_unit_id}", "organization/", "ou/")
  resource_share_arn = aws_ram_resource_share.resolver_query_share.arn
}

resource "aws_ram_resource_share" "resolver_query_share_eu_west_1" {
  provider                  = aws.modernisation-platform-eu-west-1
  allow_external_principals = false
  name                      = format("%s-resolver-log-query-share", local.application_name)
  tags                      = local.tags
}

resource "aws_ram_resource_association" "resolver_query_share_eu_west_1" {
  provider           = aws.modernisation-platform-eu-west-1
  resource_arn       = aws_route53_resolver_query_log_config.s3_eu_west_1.arn
  resource_share_arn = aws_ram_resource_share.resolver_query_share_eu_west_1.id
}

resource "aws_ram_principal_association" "resolver_query_share_eu_west_1" {
  provider           = aws.modernisation-platform-eu-west-1
  principal          = replace("${data.aws_organizations_organization.root_account.arn}/${local.environment_management.modernisation_platform_organisation_unit_id}", "organization/", "ou/")
  resource_share_arn = aws_ram_resource_share.resolver_query_share_eu_west_1.arn
}

locals {
  cortex_logging_buckets = toset(["vpc-flow-logs", "r53-resolver-logs", "generic-logs"])
}

resource "aws_s3_bucket" "logging" {
  for_each      = local.cortex_logging_buckets
  bucket_prefix = "${local.application_name}-${each.key}"
  tags          = local.tags
}

resource "aws_s3_bucket_lifecycle_configuration" "logging" {
  for_each = local.cortex_logging_buckets
  bucket   = aws_s3_bucket.logging[each.key].id

  rule {
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
    id = "rule-1"
    filter {
      prefix = ""
    }
    expiration {
      days = 14
    }
    status = "Enabled"
  }
}

data "aws_iam_policy_document" "logging-bucket" {
  for_each = local.cortex_logging_buckets
  statement {
    sid    = "AWSLogDeliveryWrite"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["delivery.logs.amazonaws.com"]
    }

    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.logging[each.key].arn}/*"]

    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceOrgID"
      values = [
        data.aws_organizations_organization.root_account.id
      ]
    }
  }
  statement {
    sid    = "AWSLogDeliveryCheck"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["delivery.logs.amazonaws.com"]
    }

    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.logging[each.key].arn]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceOrgID"
      values = [
        data.aws_organizations_organization.root_account.id
      ]
    }
  }
  statement {
    sid     = "EnforceTLSv12orHigher"
    effect  = "Deny"
    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.logging[each.key].arn,
      "${aws_s3_bucket.logging[each.key].arn}/*"
    ]
    principals {
      identifiers = ["*"]
      type        = "AWS"
    }
    condition {
      test     = "NumericLessThan"
      variable = "s3:TlsVersion"
      values   = [1.2]
    }
  }
}

resource "aws_s3_bucket_policy" "logging" {
  for_each = local.cortex_logging_buckets
  bucket   = aws_s3_bucket.logging[each.key].id
  policy   = data.aws_iam_policy_document.logging-bucket[each.key].json
}

resource "aws_s3_bucket_public_access_block" "logging" {
  for_each                = local.cortex_logging_buckets
  bucket                  = aws_s3_bucket.logging[each.key].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "logging" {
  for_each = local.cortex_logging_buckets
  bucket   = aws_s3_bucket.logging[each.key].id
  versioning_configuration {
    status = "Enabled"
  }
}

data "aws_iam_policy_document" "logging_kms" {
  for_each = local.cortex_logging_buckets

  statement {
    sid    = "Allow management access of the key to the logging account"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }

    actions   = ["kms:*"]
    resources = ["*"]
  }

  statement {
    sid    = "Allow AWS Log Delivery to use the key"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["delivery.logs.amazonaws.com"]
    }

    actions = [
      "kms:Decrypt",
      "kms:GenerateDataKey"
    ]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceOrgID"
      values = [
        data.aws_organizations_organization.root_account.id
      ]
    }
  }
}

resource "aws_kms_key" "logging" {
  for_each                = local.cortex_logging_buckets
  description             = "KMS key for ${local.application_name}-${each.key} S3 bucket encryption"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.logging_kms[each.key].json
  tags                    = local.tags
}

resource "aws_kms_alias" "logging" {
  for_each      = local.cortex_logging_buckets
  name          = "alias/${local.application_name}-${each.key}"
  target_key_id = aws_kms_key.logging[each.key].key_id
}

resource "aws_s3_bucket_server_side_encryption_configuration" "logging" {
  for_each = local.cortex_logging_buckets
  bucket   = aws_s3_bucket.logging[each.key].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.logging[each.key].arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_sqs_queue" "logging" {
  for_each                = local.cortex_logging_buckets
  name_prefix             = "${local.application_name}-${each.key}"
  sqs_managed_sse_enabled = true
  tags                    = local.tags
}

resource "aws_sqs_queue_policy" "logging" {
  for_each  = local.cortex_logging_buckets
  policy    = data.aws_iam_policy_document.logging-sqs[each.key].json
  queue_url = aws_sqs_queue.logging[each.key].url
}

data "aws_iam_policy_document" "logging-sqs" {
  for_each = local.cortex_logging_buckets
  statement {
    sid    = "AllowSendMessage"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["s3.amazonaws.com"]
    }
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.logging[each.key].arn]
    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [aws_s3_bucket.logging[each.key].arn]
    }
  }
}

resource "aws_s3_bucket_notification" "logging" {
  for_each = local.cortex_logging_buckets
  bucket   = aws_s3_bucket.logging[each.key].id
  queue {
    queue_arn = aws_sqs_queue.logging[each.key].arn
    events    = ["s3:ObjectCreated:*"]
  }
}

locals {

  cortex_topic_names = [
    { name = "modplatform", channel_id = "C02PFCG8M1R" },
    { name = "secops", channel_id = "C082F6H8A2Z" }
  ]

  max_queue_message_age = 3600
}

resource "aws_cloudwatch_metric_alarm" "sqs_cortex_age_of_oldest_message" {
  for_each            = local.cortex_logging_buckets
  alarm_name          = "${each.key}-ApproximateAgeOfOldestMessage"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "1"
  metric_name         = "ApproximateAgeOfOldestMessage"
  namespace           = "AWS/SQS"
  period              = "300"
  statistic           = "Maximum"
  threshold           = local.max_queue_message_age
  alarm_description   = "Alarm for ApproximateAgeOfOldestMessage over ${local.max_queue_message_age} seconds for SQS queue ${each.key}"
  treat_missing_data  = "notBreaching"
  dimensions = {
    QueueName = aws_sqs_queue.logging[each.key].name
  }
  alarm_actions = [for topic in local.cortex_topic_names : aws_sns_topic.cortex_sqs_sns_topic[topic.name].arn]
  tags          = local.tags
}

resource "aws_kms_key" "sns_kms_key" {
  description         = "KMS key for SQS SNS topic encryption"
  enable_key_rotation = true
  policy              = data.aws_iam_policy_document.sns_kms_policy.json
}

resource "aws_kms_alias" "sns_kms_alias" {
  name          = "alias/sqs-sns-kms-key"
  target_key_id = aws_kms_key.sns_kms_key.id
}

data "aws_iam_policy_document" "sns_kms_policy" {
  statement {
    sid    = "Allow management access of the key to the core-logging account"
    effect = "Allow"
    actions = [
      "kms:*"
    ]
    resources = ["*"]
    principals {
      type = "AWS"
      identifiers = [
        data.aws_caller_identity.current.account_id
      ]
    }
  }
  statement {
    sid    = "Allow SNS service to use the key"
    effect = "Allow"
    actions = [
      "kms:GenerateDataKey*",
      "kms:Decrypt"
    ]
    resources = ["*"]
    principals {
      type        = "Service"
      identifiers = ["sns.amazonaws.com"]
    }
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }
}

resource "aws_sns_topic_policy" "sqs_sns_topic_policy" {
  for_each = { for topic in local.cortex_topic_names : topic.name => topic }
  arn      = aws_sns_topic.cortex_sqs_sns_topic[each.key].arn
  policy   = data.aws_iam_policy_document.sqs_sns_topic_policy[each.key].json
}

data "aws_iam_policy_document" "sqs_sns_topic_policy" {
  for_each  = { for topic in local.cortex_topic_names : topic.name => topic }
  policy_id = "${each.value.name}-sqs-sns-topic-policy"
  statement {
    sid    = "Allow topic owner to manage sns topic"
    effect = "Allow"
    actions = [
      "sns:Publish",
      "sns:RemovePermission",
      "sns:SetTopicAttributes",
      "sns:DeleteTopic",
      "sns:ListSubscriptionsByTopic",
      "sns:GetTopicAttributes",
      "sns:Receive",
      "sns:AddPermission",
      "sns:Subscribe"
    ]
    resources = [aws_sns_topic.cortex_sqs_sns_topic[each.key].arn]
    principals {
      type = "AWS"
      identifiers = [
        "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
      ]
    }
  }
}

resource "aws_sns_topic" "cortex_sqs_sns_topic" {
  for_each          = { for topic in local.cortex_topic_names : topic.name => topic }
  name              = "${each.value.name}-sqs-sns-topic"
  kms_master_key_id = aws_kms_key.sns_kms_key.id
  tags              = merge(local.tags, try(each.value.tags, {}))
}

module "mp-sqs-sns-chatbot" {
  for_each         = { for topic in local.cortex_topic_names : topic.name => topic }
  source           = "github.com/ministryofjustice/modernisation-platform-terraform-aws-chatbot?ref=0ec33c7bfde5649af3c23d0834ea85c849edf3ac"
  slack_channel_id = each.value.channel_id
  sns_topic_arns = each.key == "modplatform" ? [
    aws_sns_topic.cortex_sqs_sns_topic[each.key].arn,
    aws_sns_topic.ip_usage_alerts.arn
  ] : [aws_sns_topic.cortex_sqs_sns_topic[each.key].arn]
  tags             = merge(local.tags, try(each.value.tags, {}))
  application_name = "${each.value.name}-sqs-alarm-chatbot"
}

resource "aws_cloudwatch_log_destination" "waf_logs" {
  name       = "waf-logs-destination"
  role_arn   = aws_iam_role.cwl_to_firehose.arn
  target_arn = aws_kinesis_firehose_delivery_stream.waf_logs_to_s3.arn

  depends_on = [
    aws_kinesis_firehose_delivery_stream.waf_logs_to_s3,
    aws_iam_role_policy.cwl_to_firehose_policy
  ]
}

resource "aws_cloudwatch_log_destination_policy" "waf_logs" {
  destination_name = aws_cloudwatch_log_destination.waf_logs.name
  access_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect    = "Allow",
      Principal = "*",
      Action    = "logs:PutSubscriptionFilter",
      Resource  = aws_cloudwatch_log_destination.waf_logs.arn,
      Condition = {
        StringEquals = {
          "aws:PrincipalOrgID" = data.aws_organizations_organization.current.id
        }
      }
    }]
  })
}

resource "aws_iam_role" "cwl_to_firehose" {
  name = "CWLtoFirehoseRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement : [{
      Effect = "Allow",
      Principal : {
        Service = "logs.amazonaws.com"
      },
      Action : "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "cwl_to_firehose_policy" {
  name = "Permissions-Policy-For-CWL"
  role = aws_iam_role.cwl_to_firehose.name

  policy = jsonencode({
    Version = "2012-10-17",
    Statement : [{
      Effect   = "Allow",
      Action   = ["firehose:*"],
      Resource = [aws_kinesis_firehose_delivery_stream.waf_logs_to_s3.arn]
    }]
  })
}

resource "aws_iam_role" "firehose_to_s3" {
  name = "firehose_to_s3"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = [
            "firehose.amazonaws.com",
            "logs.amazonaws.com"
          ]
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "firehose_to_s3_policy" {
  role = aws_iam_role.firehose_to_s3.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:PutObjectAcl"
        ]
        Resource = "${module.s3-bucket-modernisation-platform-waf-logs.bucket.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = aws_kms_key.s3_modernisation_platform_waf_logs.arn
      },
      {
        Effect = "Allow"
        Action = [
          "firehose:PutRecord",
          "firehose:PutRecordBatch"
        ]
        Resource = "arn:aws:firehose:eu-west-2:${data.aws_caller_identity.current.account_id}:deliverystream/waf-logs-to-s3"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/kinesisfirehose/waf-logs-to-s3:*"
      }
    ]
  })
}

resource "aws_kinesis_firehose_delivery_stream" "waf_logs_to_s3" {
  name        = "waf-logs-to-s3"
  destination = "extended_s3"

  extended_s3_configuration {
    role_arn           = aws_iam_role.firehose_to_s3.arn
    bucket_arn         = module.s3-bucket-modernisation-platform-waf-logs.bucket.arn
    buffering_size     = 5
    buffering_interval = 300
    compression_format = "UNCOMPRESSED"
    kms_key_arn        = aws_kms_key.s3_modernisation_platform_waf_logs.arn
  }
}

module "s3-bucket-modernisation-platform-waf-logs" {
  source = "github.com/ministryofjustice/modernisation-platform-terraform-s3-bucket?ref=9facf9fc8f8b8e3f93ffbda822028534b9a75399"
  providers = {
    aws.bucket-replication = aws.modernisation-platform-eu-west-1
  }

  bucket_name                = "modernisation-platform-waf-logs"
  replication_bucket         = "modernisation-platform-waf-logs-replication"
  suffix_name                = "-waf-logs"
  custom_kms_key             = aws_kms_key.s3_modernisation_platform_waf_logs.arn
  custom_replication_kms_key = aws_kms_key.s3_modernisation_platform_waf_logs_eu_west_1_replication.arn

  replication_enabled = true
  replication_region  = "eu-west-1"
  versioning_enabled  = true

  lifecycle_rule = [
    {
      id      = "main"
      enabled = "Enabled"
      prefix  = ""
      tags    = {}
      transition = [
        {
          days          = 90
          storage_class = "STANDARD_IA"
        },
        {
          days          = 365
          storage_class = "GLACIER"
        }
      ]
      expiration = {
        days = 730
      }
      noncurrent_version_transition = [
        {
          days          = 90
          storage_class = "STANDARD_IA"
        },
        {
          days          = 365
          storage_class = "GLACIER"
        }
      ]
      noncurrent_version_expiration = {
        days = 730
      }
    }
  ]

  tags = local.tags

  bucket_policy = [data.aws_iam_policy_document.modernisation_platform_waf_logs_bucket_policy.json]
}

data "aws_iam_policy_document" "modernisation_platform_waf_logs_bucket_policy" {
  statement {
    sid       = "AllowOrgFirehosePut"
    effect    = "Allow"
    actions   = ["s3:PutObject"]
    resources = ["${module.s3-bucket-modernisation-platform-waf-logs.bucket.arn}/*"]
    principals {
      type        = "Service"
      identifiers = ["firehose.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:PrincipalOrgID"
      values   = [data.aws_organizations_organization.current.id]
    }
  }

  statement {
    sid       = "DenyUnencryptedObjectUploads"
    effect    = "Deny"
    actions   = ["s3:PutObject"]
    resources = ["${module.s3-bucket-modernisation-platform-waf-logs.bucket.arn}/*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Null"
      variable = "s3:x-amz-server-side-encryption"
      values   = ["true"]
    }
  }

  statement {
    sid       = "AllowOrgListBucket"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [module.s3-bucket-modernisation-platform-waf-logs.bucket.arn]
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:PrincipalOrgID"
      values   = [data.aws_organizations_organization.current.id]
    }
  }
}

resource "aws_kms_key" "s3_modernisation_platform_waf_logs" {
  description             = "KMS key for modernisation platform waf logs bucket"
  policy                  = data.aws_iam_policy_document.kms_logging_modernisation_platform_waf_logs.json
  enable_key_rotation     = true
  deletion_window_in_days = 30
  tags                    = local.tags
}

resource "aws_kms_alias" "s3_modernisation_platform_waf_logs" {
  name          = "alias/s3-modernisation-platform-waf-logs"
  target_key_id = aws_kms_key.s3_modernisation_platform_waf_logs.id
}

data "aws_iam_policy_document" "kms_logging_modernisation_platform_waf_logs" {

  statement {
    sid       = "AllowKeyAdmin"
    effect    = "Allow"
    actions   = ["kms:*"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = [data.aws_caller_identity.current.account_id]
    }
  }

  statement {
    sid    = "AllowFirehoseAndLogsEncrypt"
    effect = "Allow"
    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:GenerateDataKey*",
      "kms:DescribeKey"
    ]
    resources = ["*"]
    principals {
      type = "Service"
      identifiers = [
        "firehose.amazonaws.com",
        "logs.${data.aws_region.current.region}.amazonaws.com"
      ]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:PrincipalOrgID"
      values   = [data.aws_organizations_organization.current.id]
    }
  }

  statement {
    sid    = "AllowCortexXsiamDecrypt"
    effect = "Allow"
    actions = [
      "kms:Decrypt",
      "kms:DescribeKey"
    ]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.cortex_xsiam_role.arn]
    }
  }

  statement {
    sid    = "AllowSQSDecrypt"
    effect = "Allow"
    actions = [
      "kms:Decrypt",
      "kms:DescribeKey"
    ]
    resources = ["*"]
    principals {
      type        = "Service"
      identifiers = ["sqs.amazonaws.com"]
    }
  }

  statement {
    sid    = "AllowS3Replication"
    effect = "Allow"
    actions = [
      "kms:Decrypt",
      "kms:Encrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey"
    ]
    resources = ["*"]
    principals {
      type = "AWS"
      identifiers = [
        format(
          "arn:aws:sts::%s:assumed-role/AWSS3BucketReplication-waf-logs/s3-replication",
          data.aws_caller_identity.current.account_id
        )
      ]
    }
  }
}

resource "aws_kms_key" "s3_modernisation_platform_waf_logs_eu_west_1_replication" {
  provider                = aws.modernisation-platform-eu-west-1
  description             = "KMS key for modernisation platform waf logs bucket replication (eu-west-1)"
  policy                  = data.aws_iam_policy_document.kms_logging_modernisation_platform_waf_logs_replication.json
  enable_key_rotation     = true
  deletion_window_in_days = 30
  tags                    = local.tags
}

resource "aws_kms_alias" "s3_logging_modernisation_platform_waf_logs_eu_west_1_replication" {
  provider      = aws.modernisation-platform-eu-west-1
  name          = "alias/s3-modernisation-platform-waf-logs-eu-west-1-replication"
  target_key_id = aws_kms_key.s3_modernisation_platform_waf_logs_eu_west_1_replication.id
}

data "aws_iam_policy_document" "kms_logging_modernisation_platform_waf_logs_replication" {

  statement {
    sid       = "AllowKeyAdmin"
    effect    = "Allow"
    actions   = ["kms:*"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = [data.aws_caller_identity.current.account_id]
    }
  }

  statement {
    sid    = "AllowS3Replication"
    effect = "Allow"
    actions = [
      "kms:Decrypt",
      "kms:Encrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey"
    ]
    resources = ["*"]
    principals {
      type = "AWS"
      identifiers = [
        format(
          "arn:aws:sts::%s:assumed-role/AWSS3BucketReplication-waf-logs/s3-replication",
          data.aws_caller_identity.current.account_id
        )
      ]
    }
  }
}

resource "aws_sqs_queue" "mp_modernisation_platform_waf_logs_queue" {
  name                       = "mp_modernisation_platform_waf_logs_queue"
  sqs_managed_sse_enabled    = true
  delay_seconds              = 0
  max_message_size           = 262144
  message_retention_seconds  = 345600
  visibility_timeout_seconds = 30
}

data "aws_iam_policy_document" "modernisation_platform_waf_logs_queue_policy_document" {
  statement {
    sid    = "AllowSendMessage"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["s3.amazonaws.com"]
    }
    actions = ["sqs:SendMessage"]
    resources = [
      aws_sqs_queue.mp_modernisation_platform_waf_logs_queue.arn
    ]
    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [module.s3-bucket-modernisation-platform-waf-logs.bucket.arn]
    }
  }
}

resource "aws_sqs_queue_policy" "modernisation_platform_waf_logs_queue_policy" {
  queue_url = aws_sqs_queue.mp_modernisation_platform_waf_logs_queue.id
  policy    = data.aws_iam_policy_document.modernisation_platform_waf_logs_queue_policy_document.json
}

resource "aws_s3_bucket_notification" "modernisation_platform_waf_logs_bucket_notification" {
  bucket = module.s3-bucket-modernisation-platform-waf-logs.bucket.id
  queue {
    queue_arn = aws_sqs_queue.mp_modernisation_platform_waf_logs_queue.arn
    events    = ["s3:ObjectCreated:*"]
  }
}

module "core_monitoring" {
  source                     = "../../modules/core-monitoring"
  pagerduty_integration_keys = local.pagerduty_integration_keys
}

module "observability_platform_tenant" {
  source = "github.com/ministryofjustice/terraform-aws-observability-platform-tenant?ref=f69b36c79ba18976d8e500e7cf61cf407158eb61"

  observability_platform_account_id = local.environment_management.account_ids["observability-platform-production"]

  additional_policies = {
    additional_athena_policy = aws_iam_policy.additional_athena_policy.arn
  }

  tags = local.tags
}

resource "aws_iam_role" "grafana_athena" {
  name               = "grafana-athena"
  assume_role_policy = data.aws_iam_policy_document.grafana_athena_assume_role_policy.json
}

data "aws_iam_policy_document" "grafana_athena_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["athena.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "grafana_athena_policy" {
  statement {
    sid    = "s3Access"
    effect = "Allow"

    actions = [
      "s3:GetObject",
      "s3:ListBucket",
      "s3:PutObject"

    ]

    resources = [
      module.s3_moj_cur_reports_modplatform.bucket.arn,
      "${module.s3_moj_cur_reports_modplatform.bucket.arn}/*"
    ]

    principals {
      type = "AWS"
      identifiers = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_iam_role_policy_attachment" "grafana_athena_attachment" {
  role       = aws_iam_role.grafana_athena.id
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonGrafanaAthenaAccess"
}

module "s3_moj_cur_reports_modplatform" {
  source              = "github.com/ministryofjustice/modernisation-platform-terraform-s3-bucket?ref=9facf9fc8f8b8e3f93ffbda822028534b9a75399"
  bucket_prefix       = "moj-cur-reports-modplatform-"
  versioning_enabled  = true
  ownership_controls  = "BucketOwnerEnforced"
  replication_enabled = false
  custom_kms_key      = aws_kms_alias.moj_cur_reports.arn
  bucket_policy       = [data.aws_iam_policy_document.moj_cur_bucket_replication_policy.json]
  providers = {
    aws.bucket-replication = aws
  }

  lifecycle_rule = [
    {
      id      = "main"
      enabled = "Enabled"
      prefix  = ""

      tags = {
        rule      = "log"
        autoclean = "true"
      }

      transition = [
        {
          days          = 90
          storage_class = "STANDARD_IA"
          }, {
          days          = 365
          storage_class = "GLACIER"
        }
      ]

      expiration = {
        days = 730
      }

      noncurrent_version_transition = [
        {
          days          = 90
          storage_class = "STANDARD_IA"
          }, {
          days          = 365
          storage_class = "GLACIER"
        }
      ]

      noncurrent_version_expiration = {
        days = 730
      }
    }
  ]
  tags = local.tags
}

data "aws_iam_policy_document" "moj_cur_bucket_replication_policy" {
  statement {
    sid    = "ReplicationPermissions"
    effect = "Allow"
    principals {
      type = "AWS"
      identifiers = [
        "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root",
        "arn:aws:iam::${data.aws_organizations_organization.root_account.master_account_id}:role/moj-cur-reports-replication-role"
      ]
    }
    actions = [
      "s3:GetBucketVersioning",
      "s3:GetObjectVersionTagging",
      "s3:List*",
      "s3:ObjectOwnerOverrideToBucketOwner",
      "s3:PutBucketVersioning",
      "s3:ReplicateDelete",
      "s3:ReplicateObject",
      "s3:ReplicateTags"
    ]
    resources = [
      module.s3_moj_cur_reports_modplatform.bucket.arn,
      "${module.s3_moj_cur_reports_modplatform.bucket.arn}/*"
    ]
  }
}

resource "aws_athena_workgroup" "mod_platform_cur_reports" {
  name = "mod-platform-cur-reports"

  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = true

    result_configuration {
      output_location = "s3://${module.s3_moj_cur_reports_modplatform.bucket.id}/workgroup/"
      encryption_configuration {
        encryption_option = "SSE_S3"
      }
    }
  }
}

data "aws_iam_policy_document" "crawler_assume_permission" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["glue.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

data "aws_iam_policy" "glue_service_role_policy" {
  arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

data "aws_iam_policy_document" "additional_athena_policy" {
  statement {
    sid    = "AthenaQueryAccess"
    effect = "Allow"
    actions = [
      "athena:GetDatabase",
      "athena:GetDataCatalog",
      "athena:GetQueryExecution",
      "athena:GetQueryResults",
      "athena:GetTableMetadata",
      "athena:GetWorkGroup",
      "athena:ListDatabases",
      "athena:ListDataCatalogs",
      "athena:ListWorkGroups",
      "athena:ListTableMetadata",
      "athena:StartQueryExecution",
      "athena:StopQueryExecution"
    ]
    resources = ["*"]
  }
  statement {
    sid    = "GluePermission"
    effect = "Allow"
    actions = [
      "glue:BatchGetPartition",
      "glue:CreateTable",
      "glue:GetDatabase",
      "glue:GetDatabases",
      "glue:GetTable",
      "glue:GetTables",
      "glue:GetPartition",
      "glue:GetPartitions",
      "glue:ImportCatalogToGlue",
      "glue:UpdateDatabase",
      "glue:UpdateTable",
    ]
    resources = ["*"]
  }
  statement {
    sid    = "AthenaS3Access"
    effect = "Allow"
    actions = [
      "s3:AbortMultipartUpload",
      "s3:GetBucketLocation",
      "s3:GetObject",
      "s3:ListBucket",
      "s3:ListBucketMultipartUploads",
      "s3:ListMultipartUploadParts",
      "s3:PutObject"
    ]
    resources = [
      module.s3_moj_cur_reports_modplatform.bucket.arn,
      "${module.s3_moj_cur_reports_modplatform.bucket.arn}/*"
    ]
  }
  statement {
    sid     = "AthenaCURReportsAccess"
    effect  = "Allow"
    actions = ["s3:GetObject", "s3:ListBucket"]
    resources = [
      module.s3_moj_cur_reports_modplatform.bucket.arn,
      "${module.s3_moj_cur_reports_modplatform.bucket.arn}/*"
    ]
  }

  statement {
    sid       = "S3DecryptPermission"
    effect    = "Allow"
    actions   = ["kms:Decrypt"]
    resources = ["*"]
  }

  statement {
    sid    = "CloudWatchPermission"
    effect = "Allow"
    actions = [
      "logs:AssociateKmsKey",
      "logs:CreateLogStream",
      "logs:CreateLogGroup",
      "logs:PutLogEvents",
    ]
    resources = [
      "arn:aws:logs:*:*:*"
    ]
  }
}

data "archive_file" "cur_initializer_lambda_code" {
  type        = "zip"
  source_file = "lambda_cur/moj_cur_crawler_lambda.py"
  output_path = "lambda_cur/moj_cur_crawler_lambda.zip"
}

data "aws_iam_policy_document" "crawler_lambda_assume" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

data "aws_iam_policy_document" "crawler_lambda_policy" {
  statement {
    sid    = "CloudWatch"
    effect = "Allow"
    actions = [
      "logs:AssociateKmsKey",
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["${aws_cloudwatch_log_group.default.arn}:*"]
  }

  statement {
    sid    = "Glue"
    effect = "Allow"
    actions = [
      "glue:StartCrawler",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "additional_athena_policy" {
  name   = "additional-athena-policy"
  policy = data.aws_iam_policy_document.additional_athena_policy.json
}

resource "aws_kms_key" "moj_cur_reports" {
  description         = "KMS key used to encrypt moj-cur-reports"
  enable_key_rotation = true
  multi_region        = true
  policy              = data.aws_iam_policy_document.moj_cur_reports_kms.json
  tags                = local.tags
}

resource "aws_kms_alias" "moj_cur_reports" {
  name          = "alias/moj-cur-reports-key"
  target_key_id = aws_kms_key.moj_cur_reports.key_id
}

data "aws_iam_policy_document" "moj_cur_reports_kms" {
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
    sid    = "Allow AWS S3, lambda & Logs service to use key"
    effect = "Allow"
    actions = [
      "kms:Decrypt*",
      "kms:Describe*",
      "kms:Encrypt*",
      "kms:GenerateDataKey*",
      "kms:ReEncrypt*"
    ]
    resources = [
      "*"
    ]
    principals {
      type = "Service"
      identifiers = [
        "glue.amazonaws.com",
        "lambda.amazonaws.com",
        "logs.amazonaws.com",
        "s3.amazonaws.com"
      ]
    }
  }
  statement {
    sid    = "AllowS3ReplicationSourceRoleToUseTheKey"
    effect = "Allow"
    principals {
      type = "AWS"
      identifiers = [
        "arn:aws:iam::${data.aws_organizations_organization.root_account.master_account_id}:role/moj-cur-reports-replication-role"
      ]
    }
    actions = [
      "kms:Encrypt",
      "kms:GenerateDataKey"
    ]
    resources = ["*"]
  }
}

resource "aws_glue_crawler" "cost_and_usage_report_crawler" {
  name                   = "moj-cur-reports-crawler"
  database_name          = aws_glue_catalog_database.cost_and_usage_report_db.name
  role                   = aws_iam_role.crawler_role.name
  security_configuration = aws_glue_security_configuration.cost_and_usage_report_sc.name

  s3_target {
    path = "s3://${module.s3_moj_cur_reports_modplatform.bucket.id}/CUR-ATHENA/MOJ-CUR-ATHENA/MOJ-CUR-ATHENA/"
    exclusions = [
      "**.json",
      "**.yml",
      "**.sql",
      "**.csv",
      "**.gz",
      "**.zip",
    ]
  }
  schema_change_policy {
    delete_behavior = "DELETE_FROM_DATABASE"
    update_behavior = "UPDATE_IN_DATABASE"
  }
}

resource "aws_glue_security_configuration" "cost_and_usage_report_sc" {
  name = "cost-and-usage-report-security-configuration"

  encryption_configuration {
    cloudwatch_encryption {
      cloudwatch_encryption_mode = "SSE-KMS"
      kms_key_arn                = aws_kms_alias.moj_cur_reports.arn
    }

    job_bookmarks_encryption {
      job_bookmarks_encryption_mode = "CSE-KMS"
      kms_key_arn                   = aws_kms_alias.moj_cur_reports.arn
    }

    s3_encryption {
      s3_encryption_mode = "SSE-KMS"
      kms_key_arn        = aws_kms_alias.moj_cur_reports.arn
    }
  }
}
resource "aws_iam_role" "crawler_role" {
  name               = "moj-cur-athena-crawler-role"
  assume_role_policy = data.aws_iam_policy_document.crawler_assume_permission.json
}

resource "aws_iam_role_policy_attachment" "glue_service_role_policy_attach" {
  policy_arn = data.aws_iam_policy.glue_service_role_policy.arn
  role       = aws_iam_role.crawler_role.name
}

resource "aws_iam_role_policy" "crawler" {
  name   = "moj-cur-athena-crawler-policy"
  role   = aws_iam_role.crawler_role.name
  policy = data.aws_iam_policy_document.additional_athena_policy.json
}

resource "aws_glue_catalog_database" "cost_and_usage_report_db" {
  name        = lower("moj-cur-athena-db")
  description = "Contains CUR data based on contents from the S3 bucket '${module.s3_moj_cur_reports_modplatform.bucket.id}'"
}

resource "aws_glue_catalog_table" "cur_report_status_table" {
  name          = "cost_and_usage_data_status"
  database_name = aws_glue_catalog_database.cost_and_usage_report_db.name
  table_type    = "EXTERNAL_TABLE"

  storage_descriptor {
    location      = "s3://${module.s3_moj_cur_reports_modplatform.bucket.id}/CUR-ATHENA/MOJ-CUR-ATHENA/cost_and_usage_data_status/"
    input_format  = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat"
    ser_de_info {
      serialization_library = "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe"
    }
    columns {
      name = "status"
      type = "string"
    }
  }
  depends_on = [aws_glue_catalog_database.cost_and_usage_report_db]
  lifecycle {
    ignore_changes = [
      parameters,
    ]
  }
}

resource "aws_cloudwatch_log_group" "default" {
  name              = "/aws/lambda/moj_cur_crawler_lambda"
  kms_key_id        = aws_kms_alias.moj_cur_reports.arn
  retention_in_days = 365
}

resource "aws_lambda_permission" "allow_s3_bucket" {
  statement_id   = "AllowS3ToInvokeLambda"
  action         = "lambda:InvokeFunction"
  function_name  = aws_lambda_function.cur_initializer.function_name
  source_account = data.aws_caller_identity.current.account_id
  principal      = "s3.amazonaws.com"
  source_arn     = module.s3_moj_cur_reports_modplatform.bucket.arn
}

resource "aws_iam_role" "cur_initializer_lambda_executor" {
  name               = "moj-cur-athena-lambda-executor"
  assume_role_policy = data.aws_iam_policy_document.crawler_lambda_assume.json
}

resource "aws_iam_role_policy" "crawler_policy" {
  name   = "moj-cur-athena-lambda-executor-policy"
  role   = aws_iam_role.cur_initializer_lambda_executor.name
  policy = data.aws_iam_policy_document.crawler_lambda_policy.json
}

resource "aws_lambda_function" "cur_initializer" {
  function_name                  = "moj_cur_crawler_lambda"
  filename                       = "lambda_cur/moj_cur_crawler_lambda.zip"
  handler                        = "moj_cur_crawler_lambda.lambda_handler"
  runtime                        = "python3.12"
  reserved_concurrent_executions = 1
  role                           = aws_iam_role.cur_initializer_lambda_executor.arn
  timeout                        = 30
  source_code_hash               = data.archive_file.cur_initializer_lambda_code.output_base64sha256
  kms_key_arn                    = aws_kms_key.moj_cur_reports.arn
  tracing_config {
    mode = "Active"
  }
  environment {
    variables = {
      CRAWLER_NAME = aws_glue_crawler.cost_and_usage_report_crawler.name
    }
  }
  depends_on = [aws_cloudwatch_log_group.default]
}

resource "aws_s3_bucket_notification" "cur_initializer_lambda_trigger" {
  bucket = module.s3_moj_cur_reports_modplatform.bucket.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.cur_initializer.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "CUR-ATHENA/MOJ-CUR-ATHENA/"
    filter_suffix       = ".parquet"
  }

  depends_on = [
    aws_lambda_permission.allow_s3_bucket,
  ]
}

output "vpc_cidrs" {
  value = {
    for key, value in local.networking :
    key => value
  }
}

output "non_live_data_private_route_tables" {

  value = module.vpc["non_live_data"].private_route_tables
}

output "public_route_tables" {
  value = {
    for key, value in local.networking :
    key => module.vpc[key].public_route_tables.tags["Name"]
  }
}

output "live_data_private_route_tables" {

  value = module.vpc["live_data"].private_route_tables
}

output "public_igw_route" {
  value = {
    for key, value in local.networking :
    key => module.vpc[key].public_igw_route.destination_cidr_block
  }
}

output "non_tgw_subnet_ids" {

  value = length(module.vpc["non_live_data"].non_tgw_subnet_ids)
}

output "tgw_subnet_ids" {

  value = length(module.vpc["non_live_data"].tgw_subnet_ids)
}

provider "aws" {
  region = "eu-west-2"
  assume_role {
    role_arn = "arn:aws:iam::${local.environment_management.account_ids[terraform.workspace]}:role/ModernisationPlatformAccess"
  }
  default_tags { tags = local.tags }
}

provider "aws" {
  alias  = "modernisation-platform"
  region = "eu-west-2"
  default_tags { tags = local.tags }
}

provider "aws" {
  alias  = "modernisation-platform-eu-west-1"
  region = "eu-west-1"
  assume_role {
    role_arn = "arn:aws:iam::${local.environment_management.account_ids["core-logging-production"]}:role/ModernisationPlatformAccess"
  }
  default_tags { tags = local.tags }
}

provider "aws" {
  alias  = "core-network-services"
  region = "eu-west-2"
  assume_role {
    role_arn = "arn:aws:iam::${local.environment_management.account_ids["core-network-services-production"]}:role/ModernisationPlatformAccess"
  }

  default_tags { tags = local.tags }
}

provider "aws" {
  alias  = "modernisation-secrets-read"
  region = "eu-west-2"
  assume_role {
    role_arn = "arn:aws:iam::${data.aws_ssm_parameter.modernisation_platform_account_id.value}:role/modernisation-account-limited-read-member-access"
  }
  default_tags { tags = local.tags }
}

provider "aws" {
  alias  = "aws-us-east-1"
  region = "us-east-1"
  assume_role {
    role_arn = "arn:aws:iam::${local.environment_management.account_ids[terraform.workspace]}:role/ModernisationPlatformAccess"
  }
  default_tags { tags = local.tags }
}

data "aws_ssm_parameter" "modernisation_platform_account_id" {
  provider = aws.modernisation-platform
  name     = "modernisation_platform_account_id"
}

data "aws_secretsmanager_secret" "environment_management" {
  provider = aws.modernisation-secrets-read
  name     = "environment_management"
}

data "aws_secretsmanager_secret_version" "environment_management" {
  provider  = aws.modernisation-secrets-read
  secret_id = data.aws_secretsmanager_secret.environment_management.id
}

data "aws_secretsmanager_secret" "pagerduty_integration_keys" {
  provider = aws.modernisation-secrets-read
  name     = "pagerduty_integration_keys"
}

data "aws_secretsmanager_secret_version" "pagerduty_integration_keys" {
  provider  = aws.modernisation-secrets-read
  secret_id = data.aws_secretsmanager_secret.pagerduty_integration_keys.id
}

resource "aws_ssm_parameter" "cortex_account_id" {
  lifecycle {
    ignore_changes = [insecure_value]
  }
  provider       = aws.modernisation-platform
  description    = "Account ID for Palo Alto Cortex XSIAM cross-account role."
  name           = "cortex_account_id"
  type           = "String"
  insecure_value = "Placeholder"
  tags           = local.tags
}

resource "aws_ssm_parameter" "cortex_endpoint_address" {
  lifecycle {
    ignore_changes = [insecure_value]
  }
  provider       = aws.modernisation-platform
  description    = "Endpoint Address for Palo Alto Cortex XSIAM cross-account role."
  name           = "cortex_xsiam_endpoint"
  type           = "String"
  insecure_value = "Placeholder"
  tags           = local.tags
}

resource "aws_ssm_parameter" "core_logging_bucket_arns" {
  provider    = aws.modernisation-platform
  description = "Bucket ARNs in core-logging for Palo Alto Cortex XSIAM."
  name        = "core_logging_bucket_arns"
  overwrite   = true
  type        = "String"
  insecure_value = jsonencode({
    for key in local.cortex_logging_buckets :
    key => aws_s3_bucket.logging[key].arn
  })
  tags = local.tags
}

data "aws_caller_identity" "current" {}

data "aws_ec2_transit_gateway" "transit-gateway" {
  provider = aws.core-network-services
  filter {
    name   = "options.amazon-side-asn"
    values = ["64589"]
  }
}

data "aws_ram_resource_share" "transit-gateway-shared" {
  provider = aws.core-network-services

  name           = "transit-gateway"
  resource_owner = "SELF"
}

resource "aws_ram_principal_association" "transit_gateway_association" {
  provider = aws.core-network-services

  principal          = data.aws_caller_identity.current.account_id
  resource_share_arn = data.aws_ram_resource_share.transit-gateway-shared.arn
}

module "vpc_attachment" {
  for_each = local.networking
  source   = "../../modules/ec2-tgw-attachment"
  providers = {
    aws.transit-gateway-tenant = aws
    aws.transit-gateway-host   = aws.core-network-services
  }

  transit_gateway_id = data.aws_ec2_transit_gateway.transit-gateway.id
  type               = each.key

  subnet_ids = module.vpc[each.key].tgw_subnet_ids
  vpc_id     = module.vpc[each.key].vpc_id
  vpc_name   = "${each.key}-${terraform.workspace}"

  tags = merge(
    local.tags,
    { "Name" = format("%s-%s-attachment", local.application_name, each.key) }
  )
}

terraform {
  required_providers {
    aws = {
      version = "~> 6.0"
      source  = "hashicorp/aws"
    }
    http = {
      version = "~> 3.0"
      source  = "hashicorp/http"
    }
    archive = {
      version = "~> 2.0"
      source  = "hashicorp/archive"
    }
    random = {
      version = "~> 3.0"
      source  = "hashicorp/random"
    }
  }
  required_version = "~> 1.0"
}

locals {
  networking = {
    live_data     = "10.20.128.0/19"
    non_live_data = "10.20.160.0/19"
  }
}

module "vpc" {
  for_each = local.networking
  source   = "../../modules/vpc-hub"

  vpc_cidr = each.value

  gateway = "transit"

  vpc_flow_log_iam_role       = aws_iam_role.vpc_flow_log.arn
  flow_log_s3_destination_arn = each.key == "live_data" ? local.core_logging_bucket_arns["vpc-flow-logs"] : ""

  transit_gateway_id = data.aws_ec2_transit_gateway.transit-gateway.id

  tags_common = local.tags
  tags_prefix = each.key
}