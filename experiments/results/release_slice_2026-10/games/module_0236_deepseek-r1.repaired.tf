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
  log_buckets = tomap({
    "log_bucket_name" : module.s3-bucket-cloudtrail-logging.bucket.id,
    "log_bucket_arn" : module.s3-bucket-cloudtrail-logging.bucket.arn,
    "log_bucket_policy" : module.s3-bucket-cloudtrail-logging.bucket_policy.policy,
  })
  log_prefix = ""
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

module "s3-bucket-modernisation-platform-waf-logs" {
  source = "github.com/ministryofjustice/modernisation-platform-terraform-s3-bucket?ref=9facf9fc8f8b8e3f93ffbda822028534b9a75399"
  providers = {
    aws.bucket-replication = aws.modernisation-platform-eu-west-1
  }
  bucket_policy              = [data.aws_iam_policy_document.modernisation_platform_waf_logs_bucket_policy.json]
  bucket_name                = "modernisation-platform-waf-logs"
  replication_bucket         = "modernisation-platform-waf-logs-replication"
  suffix_name                = "-waf-logs"
  custom_kms_key             = aws_kms_key.s3_modernisation_platform_waf_logs.arn
  custom_replication_kms_key = aws_kms_key.s3_modernisation_platform_waf_logs_eu_west_1_replication.arn
  replication_enabled        = true
  replication_region         = "eu-west-1"
  versioning_enabled         = true
  log_bucket                 = module.s3-bucket-cloudtrail-logging.bucket.id
  log_buckets = tomap({
    "log_bucket_name" : module.s3-bucket-cloudtrail-logging.bucket.id,
    "log_bucket_arn" : module.s3-bucket-cloudtrail-logging.bucket.arn,
    "log_bucket_policy" : module.s3-bucket-cloudtrail-logging.bucket_policy.policy,
  })
  log_prefix = ""
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
  log_bucket                 = module.s3-bucket-cloudtrail-logging.bucket.id
  log_buckets = tomap({
    "log_bucket_name" : module.s3-bucket-cloudtrail-logging.bucket.id,
    "log_bucket_arn" : module.s3-bucket-cloudtrail-logging.bucket.arn,
    "log_bucket_policy" : module.s3-bucket-cloudtrail-logging.bucket_policy.policy,
  })
  log_prefix = ""
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
  log_bucket                 = module.s3-bucket-cloudtrail-logging.bucket.id
  log_buckets = tomap({
    "log_bucket_name" : module.s3-bucket-cloudtrail-logging.bucket.id,
    "log_bucket_arn" : module.s3-bucket-cloudtrail-logging.bucket.arn,
    "log_bucket_policy" : module.s3-bucket-cloudtrail-logging.bucket_policy.policy,
  })
  log_prefix = ""
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
}

module "s3_moj_cur_reports_modplatform" {
  source = "github.com/ministryofjustice/modernisation-platform-terraform-s3-bucket?ref=9facf9fc8f8b8e3f93ffbda822028534b9a75399"
  bucket_prefix       = "moj-cur-reports-modplatform-"
  versioning_enabled  = true
  ownership_controls  = "BucketOwnerEnforced"
  replication_enabled = false
  custom_kms_key      = aws_kms_alias.moj_cur_reports.arn
  bucket_policy       = [data.aws_iam_policy_document.moj_cur_bucket_replication_policy.json]
  log_bucket          = module.s3-bucket-cloudtrail-logging.bucket.id
  log_buckets = tomap({
    "log_bucket_name" : module.s3-bucket-cloudtrail-logging.bucket.id,
    "log_bucket_arn" : module.s3-bucket-cloudtrail-logging.bucket.arn,
    "log_bucket_policy" : module.s3-bucket-cloudtrail-logging.bucket_policy.policy,
  })
  log_prefix = ""
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
  replication_enabled        = true
  replication_region         = "eu-west-1"
  log_bucket                 = aws_s3_bucket.logging["generic-logs"].id
  log_buckets = tomap({
    "log_bucket_name" : aws_s3_bucket.logging["generic-logs"].id,
    "log_bucket_arn" : aws_s3_bucket.logging["generic-logs"].arn,
    "log_bucket_policy" : aws_s3_bucket_policy.logging["generic-logs"].policy,
  })
  log_prefix = ""
  tags = local.tags
}

resource "aws_cloudwatch_log_group" "github_workflow_data" {
  count             = local.github_workflow_poller.enabled ? 1 : 0
  name              = "modernisation-platform-workflow-data"
  retention_in_days = local.github_workflow_poller.log_retention_days
  kms_key_id        = aws_kms_key.s3_logging_cloudtrail.arn
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
  kms_key_id        = aws_kms_key.s3_logging_cloudtrail.arn
  tags = merge(
    local.tags,
    {
      Name = "github-workflow-data-poller-logs"
    }
  )
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

resource "aws_lambda_function" "ip_usage" {
  function_name                  = "ip_usage_monitoring"
  role                           = aws_iam_role.ip_usage_lambda_exec.arn
  handler                        = "ip_usage_metrics.lambda_handler"
  runtime                        = "python3.11"
  reserved_concurrent_executions = 1
  timeout                        = 300
  tracing_config {
    mode = "Active"
  }
  filename         = data.archive_file.ip_usage_lambda.output_path
  source_code_hash = data.archive_file.ip_usage_lambda.output_base64sha256
  kms_key_arn      = aws_kms_key.ip_usage.arn
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

resource "aws_lambda_function" "cur_initializer" {
  filename                       = "lambda_cur/moj_cur_crawler_lambda.zip"
  function_name                  = "moj_cur_crawler_lambda"
  role                           = aws_iam_role.cur_initializer_lambda_executor.arn
  handler                        = "moj_cur_crawler_lambda.lambda_handler"
  runtime                        = "python3.12"
  reserved_concurrent_executions = 1
  tracing_config {
    mode = "Active"
  }
  source_code_hash = data.archive_file.cur_initializer_lambda_code.output_base64sha256
  kms_key_arn      = aws_kms_key.moj_cur_reports.arn
  timeout          = 30
  environment {
    variables = {
      CRAWLER_NAME = aws_glue_crawler.cost_and_usage_report_crawler.name
    }
  }
  depends_on = [aws_cloudwatch_log_group.default]
}

resource "aws_s3_bucket" "logging" {
  for_each = local.cortex_logging_buckets
  bucket_prefix = "${local.application_name}-${each.key}"
  versioning {
    enabled = true
  }
  logging {
    target_bucket = module.s3-bucket-cloudtrail-logging.bucket.id
    target_prefix = "logs/${each.key}/"
  }
  tags = local.tags
}