# ... (rest of the code remains the same)

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
  versioning_enabled = true
  tags = local.tags
}

# ... (rest of the code remains the same)

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
  versioning_enabled = true
  tags       = local.tags
}

# ... (rest of the code remains the same)

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
  versioning_enabled = true
  tags = local.tags
}

# ... (rest of the code remains the same)

module "s3_bucket_config_logs" {
  source = "github.com/ministryofjustice/modernisation-platform-terraform-s3-bucket?ref=9facf9fc8f8b8e3f93ffbda822028534b9a75399" # v9.0.0

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

# ... (rest of the code remains the same)

module "s3-bucket-modernisation-platform-waf-logs" {
  source = "github.com/ministryofjustice/modernisation-platform-terraform-s3-bucket?ref=9facf9fc8f8b8e3f93ffbda822028534b9a75399" # v9.0.0
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

  bucket_policy = [data.aws_iam_policy_document.modernisation_platform_waf_logs_bucket_policy.json]
}

# ... (rest of the code remains the same)

resource "aws_cloudwatch_log_group" "github_workflow_data" {
  #checkov:skip=CKV_AWS_338: Logs can be retained for less than 1 year.
  #checkov:skip=CKV_AWS_158: Log does not contain sensitive data.
  count             = local.github_workflow_poller.enabled ? 1 : 0
  name              = "modernisation-platform-workflow-data"
  retention_in_days = local.github_workflow_poller.log_retention_days
  kms_key_id        = aws_kms_key.github_workflow_data.arn

  tags = merge(
    local.tags,
    {
      Name = "modernisation-platform-workflow-data"
    }
  )
}

resource "aws_cloudwatch_log_group" "github_workflow_poller_lambda" {
  #checkov:skip=CKV_AWS_338: Logs can be retained for less than 1 year.
  #checkov:skip=CKV_AWS_158: Log does not contain sensitive data.
  count             = local.github_workflow_poller.enabled ? 1 : 0
  name              = "/aws/lambda/github-workflow-data-poller"
  retention_in_days = local.github_workflow_poller.log_retention_days
  kms_key_id        = aws_kms_key.github_workflow_poller_lambda.arn

  tags = merge(
    local.tags,
    {
      Name = "github-workflow-data-poller-logs"
    }
  )
}

# ... (rest of the code remains the same)

resource "aws_lambda_function" "github_workflow_data_poller" {
  #checkov:skip=CKV_AWS_272: Does not require code signing.
  #checkov:skip=CKV_AWS_173: Does not have sensitive environment variables.
  #checkov:skip=CKV_AWS_50: No x-ray tracing needed.
  #checkov:skip=CKV_AWS_116: Dead Letter Queue not needed.
  #checkov:skip=CKV_AWS_117: Lambda not deployed in a VPC.
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
}

# ... (rest of the code remains the same)

resource "aws_lambda_function" "ip_usage" {
  #checkov:skip=CKV_AWS_50: "X-ray tracing is not required"
  #checkov:skip=CKV_AWS_117: "Lambda is not environment specific"
  #checkov:skip=CKV_AWS_116: "DLQ not required"
  #checkov:skip=CKV_AWS_272: "Code signing not required"
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

# ... (rest of the code remains the same)

resource "aws_lambda_function" "cur_initializer" {
  #checkov:skip=CKV_AWS_50: "X-ray tracing is not required"
  #checkov:skip=CKV_AWS_117: "Lambda is not environment specific"
  #checkov:skip=CKV_AWS_116: "DLQ not required"
  #checkov:skip=CKV_AWS_272: "Code signing not required"
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

# ... (rest of the code remains the same)

resource "aws_kms_key" "github_workflow_data" {
  description             = "KMS key for github workflow data"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  policy                  = data.aws_iam_policy_document.github_workflow_data_kms.json
  tags                    = local.tags
}

resource "aws_kms_alias" "github_workflow_data" {
  name          = "alias/github-workflow-data-kms"
  target_key_id = aws_kms_key.github_workflow_data.id
}

data "aws_iam_policy_document" "github_workflow_data_kms" {
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

resource "aws_kms_key" "github_workflow_poller_lambda" {
  description             = "KMS key for github workflow poller lambda"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  policy                  = data.aws_iam_policy_document.github_workflow_poller_lambda_kms.json
  tags                    = local.tags
}

resource "aws_kms_alias" "github_workflow_poller_lambda" {
  name          = "alias/github-workflow-poller-lambda-kms"
  target_key_id = aws_kms_key.github_workflow_poller_lambda.id
}

data "aws_iam_policy_document" "github_workflow_poller_lambda_kms" {
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
    sid    = "Allow AWS Lambda service to use key"
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
        "lambda.amazonaws.com"
      ]
    }
  }
}