locals {
  create_role = local.create && var.create_function && !var.create_layer && var.create_role

  log_group_arn_regional = try(data.aws_cloudwatch_log_group.lambda[0].arn, aws_cloudwatch_log_group.lambda[0].arn, "")
  log_group_name         = try(data.aws_cloudwatch_log_group.lambda[0].name, aws_cloudwatch_log_group.lambda[0].name, "")
  log_group_arn          = local.create_role && var.lambda_at_edge ? format("arn:%s:%s:%s:%s:%s", data.aws_arn.log_group_arn[0].partition, data.aws_arn.log_group_arn[0].service, var.lambda_at_edge_logs_all_regions ? "*" : "us-east-1", data.aws_arn.log_group_arn[0].account, data.aws_arn.log_group_arn[0].resource) : local.log_group_arn_regional

  role_name   = local.create_role ? coalesce(var.role_name, var.function_name, "*") : null
  policy_name = coalesce(var.policy_name, local.role_name, "*")

  trusted_entities_services = distinct(compact(concat(
    slice(["lambda.amazonaws.com", "edgelambda.amazonaws.com"], 0, var.lambda_at_edge ? 2 : 1),
    [for service in var.trusted_entities : try(tostring(service), "")]
  )))

  trusted_entities_principals = [
    for principal in var.trusted_entities : {
      type        = principal.type
      identifiers = tolist(principal.identifiers)
    }
    if !can(tostring(principal))
  ]
}

data "aws_iam_policy_document" "assume_role" {
  count = local.create_role ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = local.trusted_entities_services
    }

    dynamic "principals" {
      for_each = local.trusted_entities_principals
      content {
        type        = principals.value.type
        identifiers = principals.value.identifiers
      }
    }
  }

  dynamic "statement" {
    for_each = var.assume_role_policy_statements

    content {
      sid         = try(statement.value.sid, replace(statement.key, "/[^0-9A-Za-z]*/", ""))
      effect      = try(statement.value.effect, null)
      actions     = try(statement.value.actions, null)
      not_actions = try(statement.value.not_actions, null)

      dynamic "principals" {
        for_each = try(statement.value.principals, [])
        content {
          type        = principals.value.type
          identifiers = principals.value.identifiers
        }
      }

      dynamic "not_principals" {
        for_each = try(statement.value.not_principals, [])
        content {
          type        = not_principals.value.type
          identifiers = not_principals.value.identifiers
        }
      }

      dynamic "condition" {
        for_each = try(statement.value.condition, [])
        content {
          test     = condition.value.test
          variable = condition.value.variable
          values   = condition.value.values
        }
      }
    }
  }
}

resource "aws_iam_role" "lambda" {
  count = local.create_role ? 1 : 0

  name                  = local.role_name
  description           = var.role_description
  path                  = var.role_path
  force_detach_policies = var.role_force_detach_policies
  permissions_boundary  = var.role_permissions_boundary
  assume_role_policy    = data.aws_iam_policy_document.assume_role[0].json
  max_session_duration  = var.role_maximum_session_duration

  tags = merge(var.tags, var.role_tags)
}

data "aws_iam_policy_document" "logs" {
  count = local.create_role && var.attach_cloudwatch_logs_policy ? 1 : 0

  statement {
    effect = "Allow"

    actions = compact([
      !var.use_existing_cloudwatch_log_group && var.attach_create_log_group_permission ? "logs:CreateLogGroup" : "",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ])

    resources = flatten([for _, v in ["%v:*", "%v:*:*"] : format(v, local.log_group_arn)])
  }
}

resource "aws_iam_role_policy" "logs" {
  count = local.create_role && var.attach_cloudwatch_logs_policy ? 1 : 0

  name   = "${local.policy_name}-logs"
  role   = aws_iam_role.lambda[0].name
  policy = data.aws_iam_policy_document.logs[0].json
}

data "aws_iam_policy_document" "dead_letter" {
  count = local.create_role && var.attach_dead_letter_policy ? 1 : 0

  statement {
    effect = "Allow"

    actions = [
      "sns:Publish",
      "sqs:SendMessage",
    ]

    resources = [
      var.dead_letter_target_arn,
    ]
  }
}

resource "aws_iam_role_policy" "dead_letter" {
  count = local.create_role && var.attach_dead_letter_policy ? 1 : 0

  name   = "${local.policy_name}-dl"
  role   = aws_iam_role.lambda[0].name
  policy = data.aws_iam_policy_document.dead_letter[0].json
}

data "aws_iam_policy" "vpc" {
  count = local.create_role && var.attach_network_policy ? 1 : 0

  arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AWSLambdaENIManagementAccess"
}

resource "aws_iam_role_policy" "vpc" {
  count = local.create_role && var.attach_network_policy ? 1 : 0

  name   = "${local.policy_name}-vpc"
  role   = aws_iam_role.lambda[0].name
  policy = data.aws_iam_policy.vpc[0].policy
}

data "aws_iam_policy" "tracing" {
  count = local.create_role && var.attach_tracing_policy ? 1 : 0

  arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

resource "aws_iam_role_policy" "tracing" {
  count = local.create_role && var.attach_tracing_policy ? 1 : 0

  name   = "${local.policy_name}-tracing"
  role   = aws_iam_role.lambda[0].name
  policy = data.aws_iam_policy.tracing[0].policy
}

data "aws_iam_policy_document" "async" {
  count = local.create_role && var.attach_async_event_policy ? 1 : 0

  statement {
    effect = "Allow"

    actions = [
      "sns:Publish",
      "sqs:SendMessage",
      "events:PutEvents",
      "lambda:InvokeFunction",
    ]

    resources = compact(distinct([var.destination_on_failure, var.destination_on_success]))
  }
}

resource "aws_iam_role_policy" "async" {
  count = local.create_role && var.attach_async_event_policy ? 1 : 0

  name   = "${local.policy_name}-async"
  role   = aws_iam_role.lambda[0].name
  policy = data.aws_iam_policy_document.async[0].json
}

resource "aws_iam_role_policy" "additional_json" {
  count = local.create_role && var.attach_policy_json ? 1 : 0

  name   = local.policy_name
  role   = aws_iam_role.lambda[0].name
  policy = var.policy_json
}

resource "aws_iam_role_policy" "additional_jsons" {
  count = local.create_role && var.attach_policy_jsons ? var.number_of_policy_jsons : 0

  name   = "${local.policy_name}-${count.index}"
  role   = aws_iam_role.lambda[0].name
  policy = var.policy_jsons[count.index]
}

resource "aws_iam_role_policy_attachment" "additional_one" {
  count = local.create_role && var.attach_policy ? 1 : 0

  role       = aws_iam_role.lambda[0].name
  policy_arn = var.policy
}

resource "aws_iam_role_policy_attachment" "additional_many" {
  count = local.create_role && var.attach_policies ? var.number_of_policies : 0

  role       = aws_iam_role.lambda[0].name
  policy_arn = var.policies[count.index]
}

data "aws_iam_policy_document" "additional_inline" {
  count = local.create_role && var.attach_policy_statements ? 1 : 0

  dynamic "statement" {
    for_each = var.policy_statements

    content {
      sid           = try(statement.value.sid, replace(statement.key, "/[^0-9A-Za-z]*/", ""))
      effect        = try(statement.value.effect, null)
      actions       = try(statement.value.actions, null)
      not_actions   = try(statement.value.not_actions, null)
      resources     = try(statement.value.resources, null)
      not_resources = try(statement.value.not_resources, null)

      dynamic "principals" {
        for_each = try(statement.value.principals, [])
        content {
          type        = principals.value.type
          identifiers = principals.value.identifiers
        }
      }

      dynamic "not_principals" {
        for_each = try(statement.value.not_principals, [])
        content {
          type        = not_principals.value.type
          identifiers = not_principals.value.identifiers
        }
      }

      dynamic "condition" {
        for_each = try(statement.value.condition, [])
        content {
          test     = condition.value.test
          variable = condition.value.variable
          values   = condition.value.values
        }
      }
    }
  }
}

resource "aws_iam_role_policy" "additional_inline" {
  count = local.create_role && var.attach_policy_statements ? 1 : 0

  name   = "${local.policy_name}-inline"
  role   = aws_iam_role.lambda[0].name
  policy = data.aws_iam_policy_document.additional_inline[0].json
}

data "aws_partition" "current" {}
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

locals {
  create = var.create && var.putin_khuylo

  archive_filename        = try(data.external.archive_prepare[0].result.filename, null)
  archive_filename_string = local.archive_filename != null ? local.archive_filename : ""

  filename = var.local_existing_package != null ? var.local_existing_package : (var.store_on_s3 ? null : local.archive_filename)

  source_code_hash = var.ignore_source_code_hash ? null : (terraform_data.package_filename_for_hash[0].output.filename != null ? try(filebase64sha256(terraform_data.package_filename_for_hash[0].output.filename), null) : null)

  s3_bucket         = var.s3_existing_package != null ? try(var.s3_existing_package.bucket, null) : (var.store_on_s3 ? var.s3_bucket : null)
  s3_key            = var.s3_existing_package != null ? try(var.s3_existing_package.key, null) : (var.store_on_s3 ? var.s3_prefix != null ? format("%s%s", var.s3_prefix, replace(local.archive_filename_string, "/^.*//", "")) : replace(local.archive_filename_string, "/^\\.//", "") : null)
  s3_object_version = var.s3_existing_package != null ? try(var.s3_existing_package.version_id, null) : (var.store_on_s3 ? try(aws_s3_object.lambda_package[0].version_id, null) : null)
}

resource "terraform_data" "package_filename_for_hash" {
  count = var.ignore_source_code_hash ? 0 : 1

  input = {
    filename = local.filename
  }

  triggers_replace = [local.filename]

  depends_on = [null_resource.archive]
}

resource "aws_lambda_function" "this" {
  count = local.create && var.create_function && !var.create_layer ? 1 : 0

  region = var.region

  function_name                      = var.function_name
  description                        = var.description
  role                               = var.create_role ? aws_iam_role.lambda[0].arn : var.lambda_role
  handler                            = var.package_type != "Zip" ? null : var.handler
  memory_size                        = var.memory_size
  reserved_concurrent_executions     = var.reserved_concurrent_executions
  runtime                            = var.package_type != "Zip" ? null : var.runtime
  layers                             = var.layers
  timeout                            = var.lambda_at_edge ? min(var.timeout, 30) : var.timeout
  publish                            = (var.lambda_at_edge || var.snap_start) ? true : var.publish
  kms_key_arn                        = var.kms_key_arn
  image_uri                          = var.image_uri
  package_type                       = var.package_type
  architectures                      = var.architectures
  code_signing_config_arn            = var.code_signing_config_arn
  replace_security_groups_on_destroy = var.replace_security_groups_on_destroy
  replacement_security_group_ids     = var.replacement_security_group_ids
  skip_destroy                       = var.skip_destroy

  dynamic "ephemeral_storage" {
    for_each = var.ephemeral_storage_size == null ? [] : [true]

    content {
      size = var.ephemeral_storage_size
    }
  }

  filename         = local.filename
  source_code_hash = local.source_code_hash

  s3_bucket         = local.s3_bucket
  s3_key            = local.s3_key
  s3_object_version = local.s3_object_version

  dynamic "image_config" {
    for_each = length(var.image_config_entry_point) > 0 || length(var.image_config_command) > 0 || var.image_config_working_directory != null ? [true] : []
    content {
      entry_point       = var.image_config_entry_point
      command           = var.image_config_command
      working_directory = var.image_config_working_directory
    }
  }

  dynamic "environment" {
    for_each = length(keys(var.environment_variables)) == 0 ? [] : [true]
    content {
      variables = var.environment_variables
    }
  }

  dynamic "dead_letter_config" {
    for_each = var.dead_letter_target_arn == null ? [] : [true]
    content {
      target_arn = var.dead_letter_target_arn
    }
  }

  dynamic "tracing_config" {
    for_each = var.tracing_mode == null ? [] : [true]
    content {
      mode = var.tracing_mode
    }
  }

  dynamic "vpc_config" {
    for_each = var.vpc_subnet_ids != null && var.vpc_security_group_ids != null ? [true] : []
    content {
      security_group_ids          = var.vpc_security_group_ids
      subnet_ids                  = var.vpc_subnet_ids
      ipv6_allowed_for_dual_stack = var.ipv6_allowed_for_dual_stack
    }
  }

  dynamic "file_system_config" {
    for_each = var.file_system_arn != null && var.file_system_local_mount_path != null ? [true] : []
    content {
      local_mount_path = var.file_system_local_mount_path
      arn              = var.file_system_arn
    }
  }

  dynamic "snap_start" {
    for_each = var.snap_start ? [true] : []

    content {
      apply_on = "PublishedVersions"
    }
  }

  dynamic "logging_config" {
    for_each = data.aws_partition.current.partition == "aws" ? [true] : []

    content {
      log_group             = var.logging_log_group
      log_format            = var.logging_log_format
      application_log_level = var.logging_log_format == "Text" ? null : var.logging_application_log_level
      system_log_level      = var.logging_log_format == "Text" ? null : var.logging_system_log_level
    }
  }

  dynamic "durable_config" {
    for_each = var.durable_config_execution_timeout != null ? [true] : []

    content {
      execution_timeout = var.durable_config_execution_timeout
      retention_period  = var.durable_config_retention_period
    }
  }

  dynamic "timeouts" {
    for_each = length(var.timeouts) > 0 ? [true] : []

    content {
      create = try(var.timeouts.create, null)
      update = try(var.timeouts.update, null)
      delete = try(var.timeouts.delete, null)
    }
  }

  dynamic "tenancy_config" {
    for_each = var.tenant_isolation_mode ? [true] : []
    content {
      tenant_isolation_mode = "PER_TENANT"
    }
  }

  tags = merge(
    var.tags,
    var.function_tags
  )

  depends_on = [
    null_resource.archive,
    aws_s3_object.lambda_package,

    aws_cloudwatch_log_group.lambda,

    aws_iam_role_policy.additional_inline,
    aws_iam_role_policy.additional_json,
    aws_iam_role_policy.additional_jsons,
    aws_iam_role_policy.async,
    aws_iam_role_policy.dead_letter,
    aws_iam_role_policy.logs,
    aws_iam_role_policy.tracing,
    aws_iam_role_policy.vpc,
    aws_iam_role_policy_attachment.additional_many,
    aws_iam_role_policy_attachment.additional_one,
  ]
}

resource "aws_lambda_layer_version" "this" {
  count = local.create && var.create_layer ? 1 : 0

  region = var.region

  layer_name   = var.layer_name
  description  = var.description
  license_info = var.license_info

  compatible_runtimes      = length(var.compatible_runtimes) > 0 ? var.compatible_runtimes : (var.runtime == "" ? null : [var.runtime])
  compatible_architectures = var.compatible_architectures
  skip_destroy             = var.layer_skip_destroy

  filename         = local.filename
  source_code_hash = local.source_code_hash

  s3_bucket         = local.s3_bucket
  s3_key            = local.s3_key
  s3_object_version = local.s3_object_version

  depends_on = [null_resource.archive, aws_s3_object.lambda_package]
}

resource "aws_s3_object" "lambda_package" {
  count = local.create && var.store_on_s3 && var.create_package ? 1 : 0

  region = var.region

  bucket        = var.s3_bucket
  acl           = var.s3_acl
  key           = local.s3_key
  source        = data.external.archive_prepare[0].result.filename
  storage_class = var.s3_object_storage_class

  server_side_encryption = var.s3_server_side_encryption
  kms_key_id             = var.s3_kms_key_id

  tags = var.s3_object_tags_only ? var.s3_object_tags : merge(var.tags, var.s3_object_tags)

  dynamic "override_provider" {
    for_each = var.s3_object_override_default_tags ? [true] : []

    content {
      default_tags {
        tags = {}
      }
    }
  }

  depends_on = [null_resource.archive]
}

data "aws_cloudwatch_log_group" "lambda" {
  count = local.create && var.create_function && !var.create_layer && var.use_existing_cloudwatch_log_group ? 1 : 0

  region = var.region

  name = coalesce(var.logging_log_group, "/aws/lambda/${var.lambda_at_edge ? "us-east-1." : ""}${var.function_name}")
}

resource "aws_cloudwatch_log_group" "lambda" {
  count = local.create && var.create_function && !var.create_layer && !var.use_existing_cloudwatch_log_group ? 1 : 0

  region = var.region

  name                        = coalesce(var.logging_log_group, "/aws/lambda/${var.lambda_at_edge ? "us-east-1." : ""}${var.function_name}")
  retention_in_days           = var.cloudwatch_logs_retention_in_days
  kms_key_id                  = var.cloudwatch_logs_kms_key_id
  skip_destroy                = var.cloudwatch_logs_skip_destroy
  log_group_class             = var.cloudwatch_logs_log_group_class
  deletion_protection_enabled = var.cloudwatch_logs_deletion_protection_enabled

  tags = merge(var.tags, var.cloudwatch_logs_tags)
}

resource "aws_lambda_provisioned_concurrency_config" "current_version" {
  count = local.create && var.create_function && !var.create_layer && var.provisioned_concurrent_executions > -1 ? 1 : 0

  region = var.region

  function_name = aws_lambda_function.this[0].function_name
  qualifier     = aws_lambda_function.this[0].version

  provisioned_concurrent_executions = var.provisioned_concurrent_executions
}

locals {
  qualifiers = zipmap(["current_version", "unqualified_alias"], [var.create_current_version_async_event_config ? true : null, var.create_unqualified_alias_async_event_config ? true : null])
}

resource "aws_lambda_function_event_invoke_config" "this" {
  for_each = { for k, v in local.qualifiers : k => v if v != null && local.create && var.create_function && !var.create_layer && var.create_async_event_config }

  region = var.region

  function_name = aws_lambda_function.this[0].function_name
  qualifier     = each.key == "current_version" ? aws_lambda_function.this[0].version : null

  maximum_event_age_in_seconds = var.maximum_event_age_in_seconds
  maximum_retry_attempts       = var.maximum_retry_attempts

  dynamic "destination_config" {
    for_each = var.destination_on_failure != null || var.destination_on_success != null ? [true] : []
    content {
      dynamic "on_failure" {
        for_each = var.destination_on_failure != null ? [true] : []
        content {
          destination = var.destination_on_failure
        }
      }

      dynamic "on_success" {
        for_each = var.destination_on_success != null ? [true] : []
        content {
          destination = var.destination_on_success
        }
      }
    }
  }
}

resource "aws_lambda_permission" "current_version_triggers" {
  for_each = { for k, v in var.allowed_triggers : k => v if local.create && var.create_function && !var.create_layer && var.create_current_version_allowed_triggers }

  region = var.region

  function_name = aws_lambda_function.this[0].function_name
  qualifier     = aws_lambda_function.this[0].version

  statement_id_prefix    = try(each.value.statement_id, each.key)
  action                 = try(each.value.action, "lambda:InvokeFunction")
  principal              = try(each.value.principal, format("%s.amazonaws.com", try(each.value.service, "")))
  principal_org_id       = try(each.value.principal_org_id, null)
  source_arn             = try(each.value.source_arn, null)
  source_account         = try(each.value.source_account, null)
  event_source_token     = try(each.value.event_source_token, null)
  function_url_auth_type = try(each.value.function_url_auth_type, null)

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lambda_permission" "unqualified_alias_triggers" {
  for_each = { for k, v in var.allowed_triggers : k => v if local.create && var.create_function && !var.create_layer && var.create_unqualified_alias_allowed_triggers }

  region = var.region

  function_name = aws_lambda_function.this[0].function_name

  statement_id_prefix    = try(each.value.statement_id, each.key)
  action                 = try(each.value.action, "lambda:InvokeFunction")
  principal              = try(each.value.principal, format("%s.amazonaws.com", try(each.value.service, "")))
  principal_org_id       = try(each.value.principal_org_id, null)
  source_arn             = try(each.value.source_arn, null)
  source_account         = try(each.value.source_account, null)
  event_source_token     = try(each.value.event_source_token, null)
  function_url_auth_type = try(each.value.function_url_auth_type, null)

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lambda_event_source_mapping" "this" {
  for_each = { for k, v in var.event_source_mapping : k => v if local.create && var.create_function && !var.create_layer && var.create_unqualified_alias_allowed_triggers }

  region = var.region

  function_name = aws_lambda_function.this[0].arn

  event_source_arn = try(each.value.event_source_arn, null)

  batch_size                         = try(each.value.batch_size, null)
  maximum_batching_window_in_seconds = try(each.value.maximum_batching_window_in_seconds, null)
  enabled                            = try(each.value.enabled, true)
  starting_position                  = try(each.value.starting_position, null)
  starting_position_timestamp        = try(each.value.starting_position_timestamp, null)
  parallelization_factor             = try(each.value.parallelization_factor, null)
  maximum_retry_attempts             = try(each.value.maximum_retry_attempts, null)
  maximum_record_age_in_seconds      = try(each.value.maximum_record_age_in_seconds, null)
  bisect_batch_on_function_error     = try(each.value.bisect_batch_on_function_error, null)
  topics                             = try(each.value.topics, null)
  queues                             = try(each.value.queues, null)
  function_response_types            = try(each.value.function_response_types, null)
  tumbling_window_in_seconds         = try(each.value.tumbling_window_in_seconds, null)

  dynamic "destination_config" {
    for_each = try(each.value.destination_arn_on_failure, null) != null ? [true] : []
    content {
      on_failure {
        destination_arn = each.value["destination_arn_on_failure"]
      }
    }
  }

  dynamic "scaling_config" {
    for_each = try([each.value.scaling_config], [])
    content {
      maximum_concurrency = try(scaling_config.value.maximum_concurrency, null)
    }
  }

  dynamic "self_managed_event_source" {
    for_each = try(each.value.self_managed_event_source, [])
    content {
      endpoints = self_managed_event_source.value.endpoints
    }
  }

  dynamic "self_managed_kafka_event_source_config" {
    for_each = try(each.value.self_managed_kafka_event_source_config, [])
    content {
      consumer_group_id = self_managed_kafka_event_source_config.value.consumer_group_id
    }
  }
  dynamic "amazon_managed_kafka_event_source_config" {
    for_each = try(each.value.amazon_managed_kafka_event_source_config, [])
    content {
      consumer_group_id = amazon_managed_kafka_event_source_config.value.consumer_group_id
    }
  }

  dynamic "source_access_configuration" {
    for_each = try(each.value.source_access_configuration, [])
    content {
      type = source_access_configuration.value["type"]
      uri  = source_access_configuration.value["uri"]
    }
  }

  dynamic "filter_criteria" {
    for_each = try(each.value.filter_criteria, null) != null ? [true] : []

    content {
      dynamic "filter" {
        for_each = try(flatten([each.value.filter_criteria]), [])

        content {
          pattern = try(filter.value.pattern, null)
        }
      }
    }
  }

  dynamic "document_db_event_source_config" {
    for_each = try(each.value.document_db_event_source_config, [])

    content {
      database_name   = document_db_event_source_config.value.database_name
      collection_name = try(document_db_event_source_config.value.collection_name, null)
      full_document   = try(document_db_event_source_config.value.full_document, null)
    }
  }

  dynamic "metrics_config" {
    for_each = try([each.value.metrics_config], [])

    content {
      metrics = metrics_config.value.metrics
    }
  }

  dynamic "provisioned_poller_config" {
    for_each = try([each.value.provisioned_poller_config], [])
    content {
      maximum_pollers = try(provisioned_poller_config.value.maximum_pollers, null)
      minimum_pollers = try(provisioned_poller_config.value.minimum_pollers, null)
    }
  }

  tags = merge(var.tags, try(each.value.tags, {}))
}

resource "aws_lambda_function_url" "this" {
  count = local.create && var.create_function && !var.create_layer && var.create_lambda_function_url ? 1 : 0

  region = var.region

  function_name = aws_lambda_function.this[0].function_name

  qualifier          = var.create_unqualified_alias_lambda_function_url ? null : aws_lambda_function.this[0].version
  authorization_type = var.authorization_type
  invoke_mode        = var.invoke_mode

  dynamic "cors" {
    for_each = length(keys(var.cors)) == 0 ? [] : [var.cors]

    content {
      allow_credentials = try(cors.value.allow_credentials, null)
      allow_headers     = try(cors.value.allow_headers, null)
      allow_methods     = try(cors.value.allow_methods, null)
      allow_origins     = try(cors.value.allow_origins, null)
      expose_headers    = try(cors.value.expose_headers, null)
      max_age           = try(cors.value.max_age, null)
    }
  }
}

resource "aws_lambda_function_recursion_config" "this" {
  count = local.create && var.create_function && !var.create_layer && var.recursive_loop == "Allow" ? 1 : 0

  region = var.region

  function_name  = aws_lambda_function.this[0].function_name
  recursive_loop = var.recursive_loop
}

resource "null_resource" "sam_metadata_aws_lambda_function" {
  count = local.create && var.create_sam_metadata && var.create_package && var.create_function && !var.create_layer ? 1 : 0

  triggers = {
    resource_name = "aws_lambda_function.this[0]"
    resource_type = "ZIP_LAMBDA_FUNCTION"

    original_source_code = jsonencode(var.source_path)

    source_code_property = "path"

    built_output_path = data.external.archive_prepare[0].result.filename
  }

  depends_on = [data.external.archive_prepare, null_resource.archive]
}

resource "null_resource" "sam_metadata_aws_lambda_layer_version" {
  count = local.create && var.create_sam_metadata && var.create_package && var.create_layer ? 1 : 0

  triggers = {
    resource_name = "aws_lambda_layer_version.this[0]"
    resource_type = "LAMBDA_LAYER"

    original_source_code = jsonencode(var.source_path)

    source_code_property = "path"

    built_output_path = data.external.archive_prepare[0].result.filename
  }

  depends_on = [data.external.archive_prepare, null_resource.archive]
}

output "lambda_function_arn" {
  description = "The ARN of the Lambda Function"
  value       = try(aws_lambda_function.this[0].arn, "")
}

output "lambda_function_arn_static" {
  description = "The static ARN of the Lambda Function. Use this to avoid cycle errors between resources (e.g., Step Functions)"
  value       = local.create && var.create_function && !var.create_layer ? "arn:${data.aws_partition.current.partition}:lambda:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:function:${var.function_name}" : ""
}

output "lambda_function_code_sha256" {
  description = "The base64-encoded representation of the source code package file"
  value       = try(aws_lambda_function.this[0].code_sha256, "")
}

output "lambda_function_invoke_arn" {
  description = "The Invoke ARN of the Lambda Function"
  value       = try(aws_lambda_function.this[0].invoke_arn, "")
}

output "lambda_function_name" {
  description = "The name of the Lambda Function"
  value       = try(aws_lambda_function.this[0].function_name, "")
}

output "lambda_function_qualified_arn" {
  description = "The ARN identifying your Lambda Function Version"
  value       = try(aws_lambda_function.this[0].qualified_arn, "")
}

output "lambda_function_qualified_invoke_arn" {
  description = "The Invoke ARN identifying your Lambda Function Version"
  value       = try(aws_lambda_function.this[0].qualified_invoke_arn, "")
}

output "lambda_function_version" {
  description = "Latest published version of Lambda Function"
  value       = try(aws_lambda_function.this[0].version, "")
}

output "lambda_function_last_modified" {
  description = "The date Lambda Function resource was last modified"
  value       = try(aws_lambda_function.this[0].last_modified, "")
}

output "lambda_function_kms_key_arn" {
  description = "The ARN for the KMS encryption key of Lambda Function"
  value       = try(aws_lambda_function.this[0].kms_key_arn, "")
}

output "lambda_function_source_code_hash" {
  description = "The user-defined hash of the source code package file"
  value       = try(aws_lambda_function.this[0].source_code_hash, "")
}

output "lambda_function_source_code_size" {
  description = "The size in bytes of the function .zip file"
  value       = try(aws_lambda_function.this[0].source_code_size, "")
}

output "lambda_function_signing_job_arn" {
  description = "ARN of the signing job"
  value       = try(aws_lambda_function.this[0].signing_job_arn, "")
}

output "lambda_function_signing_profile_version_arn" {
  description = "ARN of the signing profile version"
  value       = try(aws_lambda_function.this[0].signing_profile_version_arn, "")
}

output "lambda_function_url" {
  description = "The URL of the Lambda Function URL"
  value       = try(aws_lambda_function_url.this[0].function_url, "")
}

output "lambda_function_url_id" {
  description = "The Lambda Function URL generated id"
  value       = try(aws_lambda_function_url.this[0].url_id, "")
}

output "lambda_layer_arn" {
  description = "The ARN of the Lambda Layer with version"
  value       = try(aws_lambda_layer_version.this[0].arn, "")
}

output "lambda_layer_layer_arn" {
  description = "The ARN of the Lambda Layer without version"
  value       = try(aws_lambda_layer_version.this[0].layer_arn, "")
}

output "lambda_layer_code_sha256" {
  description = "The base64-encoded representation of the Lambda Layer source code package file"
  value       = try(aws_lambda_layer_version.this[0].code_sha256, "")
}

output "lambda_layer_created_date" {
  description = "The date Lambda Layer resource was created"
  value       = try(aws_lambda_layer_version.this[0].created_date, "")
}

output "lambda_layer_source_code_hash" {
  description = "The user-defined hash of the Lambda Layer source code package file"
  value       = try(aws_lambda_layer_version.this[0].source_code_hash, "")
}

output "lambda_layer_source_code_size" {
  description = "The size in bytes of the Lambda Layer .zip file"
  value       = try(aws_lambda_layer_version.this[0].source_code_size, "")
}

output "lambda_layer_version" {
  description = "The Lambda Layer version"
  value       = try(aws_lambda_layer_version.this[0].version, "")
}

output "lambda_event_source_mapping_arn" {
  description = "The event source mapping ARN"
  value       = { for k, v in aws_lambda_event_source_mapping.this : k => v.arn }
}

output "lambda_event_source_mapping_function_arn" {
  description = "The the ARN of the Lambda function the event source mapping is sending events to"
  value       = { for k, v in aws_lambda_event_source_mapping.this : k => v.function_arn }
}

output "lambda_event_source_mapping_state" {
  description = "The state of the event source mapping"
  value       = { for k, v in aws_lambda_event_source_mapping.this : k => v.state }
}

output "lambda_event_source_mapping_state_transition_reason" {
  description = "The reason the event source mapping is in its current state"
  value       = { for k, v in aws_lambda_event_source_mapping.this : k => v.state_transition_reason }
}

output "lambda_event_source_mapping_uuid" {
  description = "The UUID of the created event source mapping"
  value       = { for k, v in aws_lambda_event_source_mapping.this : k => v.uuid }
}

output "lambda_role_arn" {
  description = "The ARN of the IAM role created for the Lambda Function"
  value       = try(aws_iam_role.lambda[0].arn, "")
}

output "lambda_role_name" {
  description = "The name of the IAM role created for the Lambda Function"
  value       = try(aws_iam_role.lambda[0].name, "")
}

output "lambda_role_unique_id" {
  description = "The unique id of the IAM role created for the Lambda Function"
  value       = try(aws_iam_role.lambda[0].unique_id, "")
}

output "lambda_cloudwatch_log_group_arn" {
  description = "The ARN of the Cloudwatch Log Group"
  value       = local.log_group_arn
}

output "lambda_cloudwatch_log_group_name" {
  description = "The name of the Cloudwatch Log Group"
  value       = local.log_group_name
}

output "local_filename" {
  description = "The filename of zip archive deployed (if deployment was from local)"
  value       = local.filename

  depends_on = [
    null_resource.archive,
  ]
}

output "s3_object" {
  description = "The map with S3 object data of zip archive deployed (if deployment was from S3)"
  value = {
    bucket     = local.s3_bucket
    key        = local.s3_key
    version_id = local.s3_object_version
  }
}

locals {
  python = (substr(pathexpand("~"), 0, 1) == "/") ? "python3" : "python.exe"
}

data "external" "archive_prepare" {
  count = var.create && var.create_package ? 1 : 0

  program = [local.python, "${path.module}/package.py", "prepare"]

  query = {
    paths = jsonencode({
      module = path.module
      root   = path.root
      cwd