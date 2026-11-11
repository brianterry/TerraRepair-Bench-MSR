```hcl
locals {
  job_retry_enabled = var.job_retry!= null && var.job_retry.enable? true : false

  job_retry = {
    prefix                      = var.prefix
    tags                        = local.tags
    aws_partition               = var.aws_partition
    architecture                = var.lambda_architecture
    runtime                     = var.lambda_runtime
    security_group_ids          = var.lambda_security_group_ids
    subnet_ids                  = var.lambda_subnet_ids
    kms_key_arn                 = var.kms_key_arn
    lambda_tags                 = var.lambda_tags
    log_level                   = var.log_level
    logging_kms_key_id          = var.logging_kms_key_id
    logging_retention_in_days   = var.logging_retention_in_days
    metrics                     = var.metrics
    role_path                   = var.role_path
    role_permissions_boundary   = var.role_permissions_boundary
    s3_bucket                   = var.lambda_s3_bucket
    s3_key                      = var.runners_lambda_s3_key
    s3_object_version           = var.runners_lambda_s3_object_version
    zip                         = var.lambda_zip
    tracing_config              = var.tracing_config
    github_app_parameters       = var.github_app_parameters
    enable_organization_runners = var.enable_organization_runners
    sqs_build_queue             = var.sqs_build_queue
    ghes_url                    = var.ghes_url
  }
}

module "job_retry" {
  source = "./job-retry"
  count  = local.job_retry_enabled? 1 : 0

  config = local.job_retry
}


locals {
  runner_log_files = (
    var.runner_log_files!= null
   ? var.runner_log_files
    : [
      {
        "prefix_log_group" : true,
        "file_path" : "/var/log/messages",
        "log_group_name" : "messages",
        "log_stream_name" : "{instance_id}"
      },
      {
        "log_group_name" : "user_data",
        "prefix_log_group" : true,
        "file_path" : var.runner_os == "windows"? "C:/UserData.log" : "/var/log/user-data.log",
        "log_stream_name" : "{instance_id}"
      },
      {
        "log_group_name" : "runner",
        "prefix_log_group" : true,
        "file_path" : var.runner_os == "windows"? "C:/actions-runner/_diag/Runner_*.log" : "/opt/actions-runner/_diag/Runner_**.log",
        "log_stream_name" : "{instance_id}"
      },
      {
        "log_group_name" : "runner-startup",
        "prefix_log_group" : true,
        "file_path" : var.runner_os == "windows"? "C:/runner-startup.log" : "/var/log/runner-startup.log",
        "log_stream_name" : "{instance_id}"
      }
    ]
  )
  logfiles = var.enable_cloudwatch_agent? [for l in local.runner_log_files : {
    "log_group_name" : l.prefix_log_group? "/github-self-hosted-runners/${var.prefix}/${l.log_group_name}" : "/${l.log_group_name}"
    "log_stream_name" : l.log_stream_name
    "file_path" : l.file_path
  }] : []

  loggroups_names = distinct([for l in local.logfiles : l.log_group_name])

}


resource "aws_ssm_parameter" "cloudwatch_agent_config_runner" {
  count = var.enable_cloudwatch_agent? 1 : 0
  name  = "${var.ssm_paths.root}/${var.ssm_paths.config}/cloudwatch_agent_config_runner"
  type  = "String"
  value = var.cloudwatch_config!= null? var.cloudwatch_config : templatefile("${path.module}/templates/cloudwatch_config.json", {
    logfiles = jsonencode(local.logfiles)
  })
  tags = local.tags
}

resource "aws_cloudwatch_log_group" "gh_runners" {
  count             = length(local.loggroups_names)
  name              = local.loggroups_names[count.index]
  retention_in_days = var.logging_retention_in_days
  kms_key_id        = var.logging_kms_key_id
  tags              = local.tags
}

resource "aws_iam_role_policy" "cloudwatch" {
  count = var.enable_cloudwatch_agent? 1 : 0
  name  = "CloudWatchLogginAndMetrics"
  role  = aws_iam_role.runner.name
  policy = templatefile("${path.module}/policies/instance-cloudwatch-policy.json",
    {
      ssm_parameter_arn = aws_ssm_parameter.cloudwatch_agent_config_runner[0].arn
    }
  )
}


locals {
  tags = merge(
    {
      "Name" = format("%s-action-runner", var.prefix)
    },
    {
      "ghr:ssm_config_path" = "${var.ssm_paths.root}/${var.ssm_paths.config}"
    },
    var.tags,
  )

  name_sg                         = var.overrides["name_sg"] == ""? local.tags["Name"] : var.overrides["name_sg"]
  name_runner                     = var.overrides["name_runner"] == ""? local.tags["Name"] : var.overrides["name_runner"]
  role_path                       = var.role_path == null? "/${var.prefix}/" : var.role_path
  instance_profile_path           = var.instance_profile_path == null? "/${var.prefix}/" : var.instance_profile_path
  lambda_zip                      = var.lambda_zip == null? "${path.module}/../../lambdas/functions/control-plane/runners.zip" : var.lambda_zip
  userdata_template               = var.userdata_template == null? local.default_userdata_template[var.runner_os] : var.userdata_template
  kms_key_arn                     = var.kms_key_arn!= null? var.kms_key_arn : ""
  s3_location_runner_distribution = var.enable_runner_binaries_syncer? "s3://${var.s3_runner_binaries.id}/${var.s3_runner_binaries.key}" : ""
  default_ami = {
    "windows" = { name = ["Windows_Server-2022-English-Full-ECS_Optimized-*"] }
    "linux"   = var.runner_architecture == "arm64"? { name = ["al2023-ami-2023.*-kernel-6.*-arm64"] } : { name = ["al2023-ami-2023.*-kernel-6.*-x86_64"] }
  }

  default_userdata_template = {
    "windows" = "${path.module}/templates/user-data.ps1"
    "linux"   = "${path.module}/templates/user-data.sh"
  }

  userdata_install_runner = {
    "windows" = "${path.module}/templates/install-runner.ps1"
    "linux"   = "${path.module}/templates/install-runner.sh"
  }

  userdata_start_runner = {
    "windows" = "${path.module}/templates/start-runner.ps1"
    "linux"   = "${path.module}/templates/start-runner.sh"
  }

  ami_kms_key_arn = var.ami_kms_key_arn!= null? var.ami_kms_key_arn : ""
  ami_filter      = merge(local.default_ami[var.runner_os], var.ami_filter)

  enable_job_queued_check = var.enable_job_queued_check == null?!var.enable_ephemeral_runners : var.enable_job_queued_check

  arn_ssm_parameters_path_config = "arn:${var.aws_partition}:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter${var.ssm_paths.root}/${var.ssm_paths.config}"

  token_path = "${var.ssm_paths.root}/${var.ssm_paths.tokens}"

  user_data = var.enable_userdata? (var.userdata_content == null? templatefile(local.userdata_template, {
    enable_debug_logging            = var.enable_user_data_debug_logging
    s3_location_runner_distribution = local.s3_location_runner_distribution
    pre_install                     = var.userdata_pre_install
    install_runner = templatefile(local.userdata_install_runner[var.runner_os], {
      S3_LOCATION_RUNNER_DISTRIBUTION = local.s3_location_runner_distribution
      RUNNER_ARCHITECTURE             = var.runner_architecture
    })
    post_install       = var.userdata_post_install
    hook_job_started   = var.runner_hook_job_started
    hook_job_completed = var.runner_hook_job_completed
    start_runner = templatefile(local.userdata_start_runner[var.runner_os], {
      metadata_tags = var.metadata_options!= null? var.metadata_options.instance_metadata_tags : "enabled"
    })
    ghes_url        = var.ghes_url
    ghes_ssl_verify = var.ghes_ssl_verify

    ## retain these for backwards compatibility
    environment                     = var.prefix
    enable_cloudwatch_agent         = var.enable_cloudwatch_agent
    ssm_key_cloudwatch_agent_config = var.enable_cloudwatch_agent? aws_ssm_parameter.cloudwatch_agent_config_runner[0].name : ""
  }) : var.userdata_content) : ""
}

data "aws_ami" "runner" {
  most_recent = "true"

  dynamic "filter" {
    for_each = local.ami_filter
    content {
      name   = filter.key
      values = filter.value
    }
  }

  owners = var.ami_owners
}

resource "aws_launch_template" "runner" {
  name = "${var.prefix}-action-runner"

  dynamic "block_device_mappings" {
    for_each = var.block_device_mappings!= null? var.block_device_mappings : []
    content {
      device_name = block_device_mappings.value.device_name

      ebs {
        delete_on_termination = block_device_mappings.value.delete_on_termination
        encrypted             = block_device_mappings.value.encrypted
        iops                  = block_device_mappings.value.iops
        kms_key_id            = block_device_mappings.value.kms_key_id
        snapshot_id           = block_device_mappings.value.snapshot_id
        throughput            = block_device_mappings.value.throughput
        volume_size           = block_device_mappings.value.volume_size
        volume_type           = block_device_mappings.value.volume_type
      }
    }
  }

  dynamic "metadata_options" {
    for_each = var.metadata_options!= null? [var.metadata_options] : []

    content {
      http_endpoint               = metadata_options.value.http_endpoint
      http_tokens                 = metadata_options.value.http_tokens
      http_put_response_hop_limit = metadata_options.value.http_put_response_hop_limit
      instance_metadata_tags      = metadata_options.value.instance_metadata_tags
    }
  }

  dynamic "metadata_options" {
    for_each = var.metadata_options!= null? [] : [0]

    content {
      instance_metadata_tags = "enabled"
    }
  }

  dynamic "credit_specification" {
    for_each = var.credit_specification!= null? [var.credit_specification] : []
    content {
      cpu_credits = credit_specification.value
    }
  }

  monitoring {
    enabled = var.enable_runner_detailed_monitoring
  }

  iam_instance_profile {
    name = aws_iam_instance_profile.runner.name
  }

  instance_initiated_shutdown_behavior = "terminate"
  image_id                             = data.aws_ami.runner.id
  key_name                             = var.key_name
  ebs_optimized                        = var.ebs_optimized

  vpc_security_group_ids =!var.associate_public_ipv4_address? compact(concat(
    var.enable_managed_runner_security_group? [aws_security_group.runner_sg[0].id] : [],
    var.runner_additional_security_group_ids,
  )) : []

  tag_specifications {
    resource_type = "instance"
    tags = merge(
      local.tags,
      {
        "Name" = format("%s", local.name_runner)
      },
      {
        "ghr:runner_name_prefix" = var.runner_name_prefix
      },
      var.runner_ec2_tags
    )
  }

  tag_specifications {
    resource_type = "volume"
    tags = merge(
      local.tags,
      {
        "Name" = format("%s", local.name_runner)
      },
      {
        "ghr:runner_name_prefix" = var.runner_name_prefix
      },
      var.runner_ec2_tags
    )
  }

  user_data = var.runner_os == "windows"? base64encode(local.user_data) : base64gzip(local.user_data)

  tags = local.tags

  update_default_version = true

  dynamic "network_interfaces" {
    for_each = var.associate_public_ipv4_address? [var.associate_public_ipv4_address] : []
    iterator = associate_public_ipv4_address
    content {
      associate_public_ip_address = associate_public_ipv4_address.value
      security_groups = compact(concat(
        var.enable_managed_runner_security_group? [aws_security_group.runner_sg[0].id] : [],
        var.runner_additional_security_group_ids,
      ))
    }
  }
}

resource "aws_security_group" "runner_sg" {
  count       = var.enable_managed_runner_security_group? 1 : 0
  name_prefix = "${var.prefix}-github-actions-runner-sg"
  description = "Github Actions Runner security group"

  vpc_id = var.vpc_id

  ingress = []

  dynamic "egress" {
    for_each = var.egress_rules
    iterator = each

    content {
      cidr_blocks      = each.value.cidr_blocks
      ipv6_cidr_blocks = each.value.ipv6_cidr_blocks
      prefix_list_ids  = each.value.prefix_list_ids
      from_port        = each.value.from_port
      protocol         = each.value.protocol
      security_groups  = each.value.security_groups
      self             = each.value.self
      to_port          = each.value.to_port
      description      = each.value.description
    }
  }

  tags = merge(
    local.tags,
    {
      "Name" = format("%s", local.name_sg)
    },
  )
}


output "launch_template" {
  value = aws_launch_template.runner
}

output "role_runner" {
  value = aws_iam_role.runner
}

output "lambda_scale_up" {
  value = aws_lambda_function.scale_up
}

output "lambda_scale_up_log_group" {
  value = aws_cloudwatch_log_group.scale_up
}

output "role_scale_up" {
  value = aws_iam_role.scale_up
}

output "lambda_scale_down" {
  value = aws_lambda_function.scale_down
}

output "lambda_scale_down_log_group" {
  value = aws_cloudwatch_log_group.scale_down
}

output "role_scale_down" {
  value = aws_iam_role.scale_down
}

output "lambda_pool" {
  value = try(module.pool[0].lambda, null)
}

output "lambda_pool_log_group" {
  value = try(module.pool[0].lambda_log_group, null)
}

output "role_pool" {
  value = try(module.pool[0].role_pool, null)
}

output "runners_log_groups" {
  description = "List of log groups from different log files of runner machine."
  value       = try(aws_cloudwatch_log_group.gh_runners, [])
}

output "logfiles" {
  value       = local.logfiles
  description = "List of logfiles to send to CloudWatch. Object description: `log_group_name`: Name of the log group, `file_path`: path to the log file, `log_stream_name`: name of the log stream."
}


data "aws_iam_policy_document" "lambda_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_policy" "ami_id_ssm_parameter_read" {
  count       = var.ami_id_ssm_parameter_name!= null? 1 : 0
  name        = "${var.prefix}-ami-id-ssm-parameter-read"
  path        = local.role_path
  description = "Allows for reading ${var.prefix} GitHub runner AMI ID from an SSM parameter"
  tags        = local.tags
  policy      = <<-JSON
    {
      "Version": "2012-10-17",
      "Statement": [
        {
          "Effect": "Allow",
          "Action": [
            "ssm:GetParameter"
          ],
          "Resource": [
            "arn:${var.aws_partition}:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter/${trimprefix(var.ami_id_ssm_parameter_name, "/")}"
          ]
        }
      ]
    }
  JSON
}

data "aws_iam_policy_document" "lambda_xray" {
  count = var.tracing_config.mode!= null? 1 : 0
  statement {
    actions = [
      "xray:BatchGetTraces",
      "xray:GetTraceSummaries",
      "xray:PutTelemetryRecords",
      "xray:PutTraceSegments"
    ]
    effect = "Allow"
    resources = [
      "*"
    ]
    sid = "AllowXRay"
  }
}


data "aws_caller_identity" "current" {}

resource "aws_iam_role" "runner" {
  name                 = "${var.prefix}-runner-role"
  assume_role_policy   = templatefile("${path.module}/policies/instance-role-trust-policy.json", {})
  path                 = local.role_path
  permissions_boundary = var.role_permissions_boundary
  tags                 = local.tags
}

resource "aws_iam_instance_profile" "runner" {
  name = "${var.prefix}-runner-profile"
  role = aws_iam_role.runner.name
  path = local.instance_profile_path
  tags = local.tags
}

resource "aws_iam_role_policy" "runner_session_manager_aws_managed" {
  name   = "runner-ssm-session"
  count  = var.enable_ssm_on_runners? 1 : 0
  role   = aws_iam_role.runner.name
  policy = templatefile("${path.module}/policies/instance-ssm-policy.json", {})
}

resource "aws_iam_role_policy" "ssm_parameters" {
  name = "runner-ssm-parameters"
  role = aws_iam_role.runner.name
  policy = templatefile("${path.module}/policies/instance-ssm-parameters-policy.json",
    {
      arn_ssm_parameters_path_tokens = "arn:${var.aws_partition}:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter${var.ssm_paths.root}/${var.ssm_paths.tokens}"
      arn_ssm_parameters_path_config = local.arn_ssm_parameters_path_config
    }
  )
}

resource "aws_iam_role_policy" "dist_bucket" {
  count = var.enable_runner_binaries_syncer? 1 : 0

  name = "distribution-bucket"
  role = aws_iam_role.runner.name
  policy = templatefile("${path.module}/policies/instance-s3-policy.json",
    {
      s3_arn = "${var.s3_runner_binaries.arn}/${var.s3_runner_binaries.key}"
    }
  )
}

resource "aws_iam_role_policy_attachment" "xray_tracing" {
  count      = var.tracing_config.mode!= null? 1 : 0
  role       = aws_iam_role.runner.name
  policy_arn = "arn:${var.aws_partition}:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

resource "aws_iam_role_policy" "describe_tags" {
  name   = "runner-describe-tags"
  role   = aws_iam_role.runner.name
  policy = file("${path.module}/policies/instance-describe-tags-policy.json")
}

resource "aws_iam_role_policy_attachment" "managed_policies" {
  count      = length(var.runner_iam_role_managed_policy_arns)
  role       = aws_iam_role.runner.name
  policy_arn = element(var.runner_iam_role_managed_policy_arns, count.index)
}


resource "aws_iam_role_policy" "ec2" {
  name   = "ec2"
  role   = aws_iam_role.runner.name
  policy = templatefile("${path.module}/policies/instance-ec2.json", {})
}

# see also logging.tf for logging and metrics policies


module "pool" {
  count = length(var.pool_config) == 0? 0 : 1

  source = "./pool"

  config = {
    prefix = var.prefix
    ghes = {
      ssl_verify = var.ghes_ssl_verify
      url        = var.ghes_url
    }
    github_app_parameters         = var.github_app_parameters
    instance_allocation_strategy  = var.instance_allocation_strategy
    instance_max_spot_price       = var.instance_max_spot_price
    instance_target_capacity_type = var.instance_target_capacity_type
    instance_types                = var.instance_types
    kms_key_arn                   = local.kms_key_arn
    ami_kms_key_arn               = local.ami_kms_key_arn
    lambda = {
      log_level                      = var.log_level
      logging_retention_in_days      = var.logging_retention_in_days
      logging_kms_key_id             = var.logging_kms_key_id
      reserved_concurrent_executions = var.pool_lambda_reserved_concurrent_executions
      s3_bucket                      = var.lambda_s3_bucket
      s3_key                         = var.runners_lambda_s3_key
      s3_object_version              = var.runners_lambda_s3_object_version
      security_group_ids             = var.lambda_security_group_ids
      subnet_ids                     = var.lambda_subnet_ids
      architecture                   = var.lambda_architecture
      memory_size                    = var.pool_lambda_memory_size
      runtime                        = var.lambda_runtime
      timeout                        = var.pool_lambda_timeout
      zip                            = local.lambda_zip
    }
    pool                      = var.pool_config
    role_path                 = local.role_path
    role_permissions_boundary = var.role_permissions_boundary
    runner = {
      disable_runner_autoupdate            = var.disable_runner_autoupdate
      ephemeral                            = var.enable_ephemeral_runners
      enable_jit_config                    = var.enable_jit_config
      enable_on_demand_failover_for_errors = var.enable_on_demand_failover_for_errors
      boot_time_in_minutes                 = var.runner_boot_time_in_minutes
      labels                               = var.runner_labels
      launch_template                      = aws_launch_template.runner
      group_name                           = var.runner_group_name
      name_prefix                          = var.runner_name_prefix
      pool_owner                           = var.pool_runner_owner
      role                                 = aws_iam_role.runner
    }
    subnet_ids                           = var.subnet_ids
    ssm_token_path                       = "${var.ssm_paths.root}/${var.ssm_paths.tokens}"
    ssm_config_path                      = "${var.ssm_paths.root}/${var.ssm_paths.config}"
    ami_id_ssm_parameter_name            = var.ami_id_ssm_parameter_name
    ami_id_ssm_parameter_read_policy_arn = var.ami_id_ssm_parameter_name!= null? aws_iam_policy.ami_id_ssm_parameter_read[0].arn : null
    tags                                 = local.tags
    lambda_tags                          = var.lambda_tags
    arn_ssm_parameters_path_config       = local.arn_ssm_parameters_path_config
  }

  aws_partition  = var.aws_partition
  tracing_config = var.tracing_config
}


resource "aws_ssm_parameter" "runner_config_run_as" {
  name  = "${var.ssm_paths.root}/${var.ssm_paths.config}/run_as"
  type  = "String"
  value = var.runner_as_root? "root" : var.runner_run_as
  tags  = local.tags
}

resource "aws_ssm_parameter" "runner_agent_mode" {
  name  = "${var.ssm_paths.root}/${var.ssm_paths.config}/agent_mode"
  type  = "String"
  value = var.enable_ephemeral_runners? "ephemeral" : "persistent"
  tags  = local.tags
}

resource "aws_ssm_parameter" "disable_default_labels" {
  name  = "${var.ssm_paths.root}/${var.ssm_paths.config}/disable_default_labels"
  type  = "String"
  value = var.runner_disable_default_labels
  tags  = local.tags
}

resource "aws_ssm_parameter" "jit_config_enabled" {
  name  = "${var.ssm_paths.root}/${var.ssm_paths.config}/enable_jit_config"
  type  = "String"
  value = var.enable_jit_config == null? var.enable_ephemeral_runners : var.enable_jit_config
  tags  = local.tags
}

resource "aws_ssm_parameter" "runner_enable_cloudwatch" {
  name  = "${var.ssm_paths.root}/${var.ssm_paths.config}/enable_cloudwatch"
  type  = "String"
  value = var.enable_cloudwatch_agent
  tags  = local.tags
}

resource "aws_ssm_parameter" "token_path" {
  name  = "${var.ssm_paths.root}/${var.ssm_paths.config}/token_path"
  type  = "String"
  value = "${var.ssm_paths.root}/${var.ssm_paths.tokens}"
  tags  = local.tags
}


locals {
  # Windows Runners can take their sweet time to do anything
  min_runtime_defaults = {
    "windows" = 15
    "linux"   = 5
  }
}
resource "aws_lambda_function" "scale_down" {
  s3_bucket         = var.lambda_s3_bucket!= null? var.lambda_s3_bucket : null
  s3_key            = var.runners_lambda_s3_key!= null? var.runners_lambda_s3_key : null
  s3_object_version = var.runners_lambda_s3_object_version!= null? var.runners_lambda_s3_object_version : null
  filename          = var.lambda_s3_bucket == null? local.lambda_zip : null
  source_code_hash  = var.lambda_s3_bucket == null? filebase64sha256(local.lambda_zip) : null
  function_name     = "${var.prefix}-scale-down"
  role              = aws_iam_role.scale_down.arn
  handler           = "index.scaleDownHandler"
  runtime           = var.lambda_runtime
  timeout           = var.lambda_timeout_scale_down
  tags              = merge(local.tags, var.lambda_tags)
  memory_size       = var.lambda_scale_down_memory_size
  architectures     = [var.lambda_architecture]

  environment {
    variables = {
      ENVIRONMENT                              = var.prefix
      ENABLE_METRIC_GITHUB_APP_RATE_LIMIT      = var.metrics.enable && var.metrics.metric.enable_github_app_rate_limit
      GHES_URL                                 = var.ghes_url
      LOG_LEVEL                                = var.log_level
      MINIMUM_RUNNING_TIME_IN_MINUTES          = coalesce(var.minimum_running_time_in_minutes, local.min_runtime_defaults[var.runner_os])
      NODE_TLS_REJECT_UNAUTHORIZED             = var.ghes_url!= null &&!var.ghes_ssl_verify? 0 : 1
      PARAMETER_GITHUB_APP_ID_NAME             = var.github_app_parameters.id.name
      PARAMETER_GITHUB_APP_KEY_BASE64_NAME     = var.github_app_parameters.key_base64.name
      POWERTOOLS_LOGGER_LOG_EVENT              = var.log_level == "debug"? "true" : "false"
      RUNNER_BOOT_TIME_IN_MINUTES              = var.runner_boot_time_in_minutes
      SCALE_DOWN_CONFIG                        = jsonencode(var.idle_config)
      POWERTOOLS_SERVICE_NAME                  = "runners-scale-down"
      POWERTOOLS_METRICS_NAMESPACE             = var.metrics.namespace
      POWERTOOLS_TRACE_ENABLED                 = var.tracing_config.mode!= null? true : false
      POWERTOOLS_TRACER_CAPTURE_HTTPS_REQUESTS = var.tracing_config.capture_http_requests
      POWERTOOLS_TRACER_CAPTURE_ERROR          = var.tracing_config.capture_error
    }
  }

  dynamic "vpc_config" {
    for_each = var.lambda_subnet_ids!= null && var.lambda_security_group_ids!= null? [true] : []
    content {
      security_group_ids = var.lambda_security_group_ids
      subnet_ids         = var.lambda_subnet_ids
    }
  }

  dynamic "tracing_config" {
    for_each = var.tracing_config.mode!= null? [true] : []
    content {
      mode = var.tracing_config.mode
    }
  }
}

resource "aws_cloudwatch_log_group" "scale_down" {
  name              = "/aws/lambda/${aws_lambda_function.scale_down.function_name}"
  retention_in_days = var.logging_retention_in_days
  kms_key_id        = var.logging_kms_key_id
  tags              = var.tags
}

resource "aws_cloudwatch_event_rule" "scale_down" {
  name                = "${var.prefix}-scale-down-rule"
  schedule_expression = var.scale_down_schedule_expression
  tags                = var.tags
}

resource "aws_cloudwatch_event_target" "scale_down" {
  rule = aws_cloudwatch_event_rule.scale_down.name
  arn  = aws_lambda_function.scale_down.arn
}

resource "aws_lambda_permission" "scale_down" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.scale_down.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.scale_down.arn
}

resource "aws_iam_role" "scale_down" {
  name                 = "${var.prefix}-action-scale-down-lambda-role"
  assume_role_policy   = data.aws_iam_policy_document.lambda_assume_role_policy.json
  path                 = local.role_path
  permissions_boundary = var.role_permissions_boundary
  tags                 = local.tags
}

resource "aws_iam_role_policy" "scale_down" {
  name = "scale-down-policy"
  role = aws_iam_role.scale_down.name
  policy = templatefile("${path.module}/policies/lambda-scale-down.json", {
    environment               = var.prefix
    github_app_id_arn         = var.github_app_parameters.id.arn
    github_app_key_base64_arn = var.github_app_parameters.key_base64.arn
    kms_key_arn               = local.kms_key_arn
  })
}

resource "aws_iam_role_policy" "scale_down_logging" {
  name = "logging-policy"
  role = aws_iam_role.scale_down.name
  policy = templatefile("${path.module}/policies/lambda-cloudwatch.json", {
    log_group_arn = aws_cloudwatch_log_group.scale_down.arn
  })
}

resource "aws_iam_role_policy_attachment" "scale_down_vpc_execution_role" {
  count      = length(var.lambda_subnet_ids) > 0? 1 : 0
  role       = aws_iam_role.scale_down.name
  policy_arn = "arn:${var.aws_partition}:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy" "scale_down_xray" {
  count  = var.tracing_config.mode!= null? 1 : 0
  name   = "xray-policy"
  policy = data.aws_iam_policy_document.lambda_xray[0].json
  role   = aws_iam_role.scale_down.name
}

resource "aws_iam_role_policy" "scale_down_dlq" {
  name = "dlq-policy"
  role = aws_iam_role.scale_down.name
  policy = jsonencode({
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Action": [
          "sqs:SendMessage"
        ],
        "Resource": [
          "arn:${var.aws_partition}:sqs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:scale-down-dlq"
        ]
      }
    ]
  })
}

resource "aws_sqs_queue" "scale_down_dlq" {
  name = "scale-down-dlq"
}

resource "aws_lambda_function" "scale_down" {
  dynamic "dead_letter_config" {
    for_each = var.tracing_config.mode!= null? [true] : []
    content {
      target_arn = aws_sqs_queue.scale_down_dlq.arn
    }
  }
}

resource "aws_lambda_function" "scale_down" {
  dynamic "environment" {
    for_each = var.tracing_config.mode!= null? [true] : []
    content {
      variables = {
        POWERTOOLS_TRACE_ENABLED = true
      }
    }
  }
}

resource "aws_lambda_function" "scale_down" {
  dynamic "reserved_concurrent_executions" {
    for_each = var.tracing_config.mode!= null? [true] : []
    content {
      value = 1
    }
  }
}

resource "aws_lambda_function" "scale_down" {
  dynamic "code_signing_config_arn" {
    for_each = var.tracing_config.mode!= null? [true] : []
    content {
      arn = "arn:${var.aws_partition}:lambda:${var.aws_region}:${data.aws_caller_identity.current.account_id}:code-signing-config:my-code-signing-config"
    }
  }
}

locals {
  job_retry_config = local.job_retry_enabled? {
    enable         = var.job_retry.enable
    maxAttempts    = var.job_retry.max_attempts
    delayInSeconds = var.job_retry.delay_in_seconds
    delayBackoff   = var.job_retry.delay_backoff
    queueUrl       = module.job_retry[0].job_retry_check_queue.url
  } : {}
}

resource "aws_lambda_function" "scale_up" {
  s3_bucket                      = var.lambda_s3_bucket!= null? var.lambda_s3_bucket : null
  s3_key                         = var.runners_lambda_s3_key!= null? var.runners_lambda_s3_key : null
  s3_object_version              = var.runners_lambda_s3_object_version!= null? var.runners_lambda_s3_object_version : null
  filename                       = var.lambda_s3_bucket == null? local.lambda_zip : null
  source_code_hash               = var.lambda_s3_bucket == null? filebase64sha256(local.lambda_zip) : null
  function_name                  = "${var.prefix}-scale-up"
  role                           = aws_iam_role.scale_up.arn
  handler                        = "index.scaleUpHandler"
  runtime                        = var.lambda_runtime
  timeout                        = var.lambda_timeout_scale_up
  reserved_concurrent_executions = var.scale_up_reserved_concurrent_executions
  memory_size                    = var.lambda_scale_up_memory_size
  tags                           = merge(local.tags, var.lambda_tags)
  architectures                  = [var.lambda_architecture]
  environment {
    variables = {
      AMI_ID_SSM_PARAMETER_NAME                = var.ami_id_ssm_parameter_name
      DISABLE_RUNNER_AUTOUPDATE                = var.disable_runner_autoupdate
      ENABLE_EPHEMERAL_RUNNERS                 = var.enable_ephemeral_runners
      ENABLE_JIT_CONFIG                        = var.enable_jit_config
      ENABLE_JOB_QUEUED_CHECK                  = local.enable_job_queued_check
      ENABLE_METRIC_GITHUB_APP_RATE_LIMIT      = var.metrics.enable && var.metrics.metric.enable_github_app_rate_limit
      ENABLE_ORGANIZATION_RUNNERS              = var.enable_organization_runners
      ENVIRONMENT                              = var.prefix
      GHES_URL                                 = var.ghes_url
      INSTANCE_ALLOCATION_STRATEGY             = var.instance_allocation_strategy
      INSTANCE_MAX_SPOT_PRICE                  = var.instance_max_spot_price
      INSTANCE_TARGET_CAPACITY_TYPE            = var.instance_target_capacity_type
      INSTANCE_TYPES                           = join(",", var.instance_types)
      LAUNCH_TEMPLATE_NAME                     = aws_launch_template.runner.name
      LOG_LEVEL                                = var.log_level
      MINIMUM_RUNNING_TIME_IN_MINUTES          = coalesce(var.minimum_running_time_in_minutes, local.min_runtime_defaults[var.runner_os])
      NODE_TLS_REJECT_UNAUTHORIZED             = var.ghes_url!= null &&!var.