data "aws_region" "current" {
  region = var.region

  count = var.create ? 1 : 0
}
data "aws_partition" "current" {
  count = var.create ? 1 : 0
}
data "aws_caller_identity" "current" {
  count = var.create ? 1 : 0
}

locals {
  account_id = try(data.aws_caller_identity.current[0].account_id, "")
  partition  = try(data.aws_partition.current[0].partition, "")
  region     = try(data.aws_region.current[0].region, "")
}

################################################################################
# Cluster
################################################################################

resource "aws_ecs_cluster" "this" {
  count = var.create ? 1 : 0

  region = var.region

  dynamic "configuration" {
    for_each = var.configuration != null ? [var.configuration] : []

    content {
      dynamic "execute_command_configuration" {
        for_each = configuration.value.execute_command_configuration != null ? [configuration.value.execute_command_configuration] : []

        content {
          kms_key_id = execute_command_configuration.value.kms_key_id

          dynamic "log_configuration" {
            for_each = execute_command_configuration.value.log_configuration != null ? [execute_command_configuration.value.log_configuration] : []

            content {
              cloud_watch_encryption_enabled = log_configuration.value.cloud_watch_encryption_enabled
              cloud_watch_log_group_name     = try(aws_cloudwatch_log_group.this[0].name, log_configuration.value.cloud_watch_log_group_name)
              s3_bucket_encryption_enabled   = log_configuration.value.s3_bucket_encryption_enabled
              s3_bucket_name                 = log_configuration.value.s3_bucket_name
              s3_key_prefix                  = log_configuration.value.s3_key_prefix
            }
          }

          logging = execute_command_configuration.value.logging
        }
      }

      dynamic "managed_storage_configuration" {
        for_each = configuration.value.managed_storage_configuration != null ? [configuration.value.managed_storage_configuration] : []

        content {
          fargate_ephemeral_storage_kms_key_id = managed_storage_configuration.value.fargate_ephemeral_storage_kms_key_id
          kms_key_id                           = managed_storage_configuration.value.kms_key_id
        }
      }
    }
  }

  name = var.name

  dynamic "service_connect_defaults" {
    for_each = var.service_connect_defaults != null ? [var.service_connect_defaults] : []

    content {
      namespace = service_connect_defaults.value.namespace
    }
  }

  dynamic "setting" {
    for_each = var.setting != null ? var.setting : []

    content {
      name  = setting.value.name
      value = setting.value.value
    }
  }

  tags = var.tags
}

################################################################################
# CloudWatch Log Group
################################################################################

locals {
  log_group_name = try(coalesce(var.cloudwatch_log_group_name, "/aws/ecs/${var.name}"), "")
}

resource "aws_cloudwatch_log_group" "this" {
  count = var.create && var.create_cloudwatch_log_group ? 1 : 0

  region = var.region

  name              = local.log_group_name
  retention_in_days = var.cloudwatch_log_group_retention_in_days
  kms_key_id        = var.cloudwatch_log_group_kms_key_id
  log_group_class   = var.cloudwatch_log_group_class

  tags = merge(
    var.tags,
    var.cloudwatch_log_group_tags,
    { Name = local.log_group_name }
  )
}

################################################################################
# Cluster Capacity Providers
################################################################################

resource "time_sleep" "this" {
  count = var.create ? 1 : 0

  create_duration = var.cluster_capacity_providers_wait_duration

  triggers = {
    capacity_provider_names = var.capacity_providers != null ? join(",", [for k, v in var.capacity_providers : aws_ecs_capacity_provider.this[k].name]) : ""
    capacity_providers = var.capacity_providers != null ? jsonencode(aws_ecs_capacity_provider.this) : ""
  }
}

resource "aws_ecs_cluster_capacity_providers" "this" {
  count = var.create ? 1 : 0

  region = var.region

  cluster_name       = aws_ecs_cluster.this[0].name
  capacity_providers = distinct(concat(var.cluster_capacity_providers, compact(split(",", time_sleep.this[0].triggers["capacity_provider_names"]))))

  dynamic "default_capacity_provider_strategy" {
    for_each = var.default_capacity_provider_strategy != null ? var.default_capacity_provider_strategy : {}

    content {
      base              = default_capacity_provider_strategy.value.base
      capacity_provider = try(coalesce(default_capacity_provider_strategy.value.name, default_capacity_provider_strategy.key))
      weight            = coalesce(default_capacity_provider_strategy.value.weight, 1)
    }
  }
}

################################################################################
# Capacity Provider
################################################################################

locals {
  managed_instances_enabled = var.capacity_providers != null ? anytrue([for k, v in var.capacity_providers : v.managed_instances_provider != null]) : false
}

resource "aws_ecs_capacity_provider" "this" {
  for_each = var.create && var.capacity_providers != null ? var.capacity_providers : {}

  region = var.region

  dynamic "auto_scaling_group_provider" {
    for_each = each.value.auto_scaling_group_provider != null ? [each.value.auto_scaling_group_provider] : []

    content {
      auto_scaling_group_arn = auto_scaling_group_provider.value.auto_scaling_group_arn
      managed_draining       = auto_scaling_group_provider.value.managed_draining

      dynamic "managed_scaling" {
        for_each = auto_scaling_group_provider.value.managed_scaling != null ? [auto_scaling_group_provider.value.managed_scaling] : []

        content {
          instance_warmup_period    = managed_scaling.value.instance_warmup_period
          maximum_scaling_step_size = managed_scaling.value.maximum_scaling_step_size
          minimum_scaling_step_size = managed_scaling.value.minimum_scaling_step_size
          status                    = managed_scaling.value.status
          target_capacity           = managed_scaling.value.target_capacity
        }
      }

      managed_termination_protection = auto_scaling_group_provider.value.managed_scaling != null ? auto_scaling_group_provider.value.managed_termination_protection : "DISABLED"
    }
  }

  dynamic "managed_instances_provider" {
    for_each = each.value.managed_instances_provider != null ? [each.value.managed_instances_provider] : []

    content {
      infrastructure_role_arn = local.create_infrastructure_iam_role ? aws_iam_role.infrastructure[0].arn : managed_instances_provider.value.infrastructure_role_arn

      dynamic "instance_launch_template" {
        for_each = managed_instances_provider.value.instance_launch_template != null ? [managed_instances_provider.value.instance_launch_template] : []

        content {
          capacity_option_type     = instance_launch_template.value.capacity_option_type
          ec2_instance_profile_arn = local.create_node_iam_instance_profile ? aws_iam_instance_profile.this[0].arn : instance_launch_template.value.ec2_instance_profile_arn

          dynamic "instance_requirements" {
            for_each = instance_launch_template.value.instance_requirements != null ? [instance_launch_template.value.instance_requirements] : []

            content {
              dynamic "accelerator_count" {
                for_each = instance_requirements.value.accelerator_count != null ? [instance_requirements.value.accelerator_count] : []

                content {
                  max = accelerator_count.value.max
                  min = accelerator_count.value.min
                }
              }

              accelerator_manufacturers = instance_requirements.value.accelerator_manufacturers
              accelerator_names         = instance_requirements.value.accelerator_names

              dynamic "accelerator_total_memory_mib" {
                for_each = instance_requirements.value.accelerator_total_memory_mib != null ? [instance_requirements.value.accelerator_total_memory_mib] : []

                content {
                  max = accelerator_total_memory_mib.value.max
                  min = accelerator_total_memory_mib.value.min
                }
              }

              accelerator_types      = instance_requirements.value.accelerator_types
              allowed_instance_types = instance_requirements.value.allowed_instance_types
              bare_metal             = instance_requirements.value.bare_metal

              dynamic "baseline_ebs_bandwidth_mbps" {
                for_each = instance_requirements.value.baseline_ebs_bandwidth_mbps != null ? [instance_requirements.value.baseline_ebs_bandwidth_mbps] : []

                content {
                  max = baseline_ebs_bandwidth_mbps.value.max
                  min = baseline_ebs_bandwidth_mbps.value.min
                }
              }

              burstable_performance                                   = instance_requirements.value.burstable_performance
              cpu_manufacturers                                       = instance_requirements.value.cpu_manufacturers
              excluded_instance_types                                 = instance_requirements.value.excluded_instance_types
              instance_generations                                    = instance_requirements.value.instance_generations
              local_storage                                           = instance_requirements.value.local_storage
              local_storage_types                                     = instance_requirements.value.local_storage_types
              max_spot_price_as_percentage_of_optimal_on_demand_price = instance_requirements.value.max_spot_price_as_percentage_of_optimal_on_demand_price

              dynamic "memory_gib_per_vcpu" {
                for_each = instance_requirements.value.memory_gib_per_vcpu != null ? [instance_requirements.value.memory_gib_per_vcpu] : []

                content {
                  max = memory_gib_per_vcpu.value.max
                  min = memory_gib_per_vcpu.value.min
                }
              }

              dynamic "memory_mib" {
                for_each = instance_requirements.value.memory_mib != null ? [instance_requirements.value.memory_mib] : []

                content {
                  max = memory_mib.value.max
                  min = memory_mib.value.min
                }
              }

              dynamic "network_bandwidth_gbps" {
                for_each = instance_requirements.value.network_bandwidth_gbps != null ? [instance_requirements.value.network_bandwidth_gbps] : []

                content {
                  max = network_bandwidth_gbps.value.max
                  min = network_bandwidth_gbps.value.min
                }
              }

              dynamic "network_interface_count" {
                for_each = instance_requirements.value.network_interface_count != null ? [instance_requirements.value.network_interface_count] : []

                content {
                  max = network_interface_count.value.max
                  min = network_interface_count.value.min
                }
              }

              on_demand_max_price_percentage_over_lowest_price = instance_requirements.value.on_demand_max_price_percentage_over_lowest_price
              require_hibernate_support                        = instance_requirements.value.require_hibernate_support
              spot_max_price_percentage_over_lowest_price      = instance_requirements.value.spot_max_price_percentage_over_lowest_price

              dynamic "total_local_storage_gb" {
                for_each = instance_requirements.value.total_local_storage_gb != null ? [instance_requirements.value.total_local_storage_gb] : []

                content {
                  max = total_local_storage_gb.value.max
                  min = total_local_storage_gb.value.min
                }
              }

              dynamic "vcpu_count" {
                for_each = instance_requirements.value.vcpu_count != null ? [instance_requirements.value.vcpu_count] : []

                content {
                  max = vcpu_count.value.max
                  min = vcpu_count.value.min
                }
              }
            }
          }

          monitoring = instance_launch_template.value.monitoring

          dynamic "network_configuration" {
            for_each = instance_launch_template.value.network_configuration != null ? [instance_launch_template.value.network_configuration] : []

            content {
              security_groups = local.create_security_group ? flatten(concat(aws_security_group.this[*].id, network_configuration.value.security_groups)) : network_configuration.value.security_groups
              subnets         = network_configuration.value.subnets
            }
          }

          dynamic "storage_configuration" {
            for_each = instance_launch_template.value.storage_configuration != null ? [instance_launch_template.value.storage_configuration] : []

            content {
              storage_size_gib = storage_configuration.value.storage_size_gib
            }
          }
        }
      }

      propagate_tags = managed_instances_provider.value.propagate_tags
    }
  }

  cluster = each.value.managed_instances_provider != null ? aws_ecs_cluster.this[0].name : null

  name = try(coalesce(each.value.name, each.key), "")

  tags = merge(
    var.tags,
    each.value.tags,
  )

  depends_on = [
    aws_iam_role_policy_attachment.task_exec,
    aws_iam_role_policy_attachment.infrastructure,
    aws_iam_role_policy_attachment.node,
    aws_vpc_security_group_ingress_rule.this,
    aws_vpc_security_group_egress_rule.this,
  ]
}

################################################################################
# Task Execution - IAM Role
################################################################################

locals {
  task_exec_iam_role_name = try(coalesce(var.task_exec_iam_role_name, "${var.name}${var.disable_v7_default_name_description ? "" : "-task-exec"}"), "")

  create_task_exec_iam_role = var.create && var.create_task_exec_iam_role
  create_task_exec_policy   = local.create_task_exec_iam_role && var.create_task_exec_policy
}

data "aws_iam_policy_document" "task_exec_assume" {
  count = local.create_task_exec_iam_role ? 1 : 0

  statement {
    sid     = "ECSTaskExecutionAssumeRole"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "task_exec" {
  count = local.create_task_exec_iam_role ? 1 : 0

  name        = var.task_exec_iam_role_use_name_prefix ? null : local.task_exec_iam_role_name
  name_prefix = var.task_exec_iam_role_use_name_prefix ? "${local.task_exec_iam_role_name}-" : null
  path        = var.task_exec_iam_role_path
  description = coalesce(var.task_exec_iam_role_description, "Task execution role for ${var.name}")

  assume_role_policy    = data.aws_iam_policy_document.task_exec_assume[0].json
  permissions_boundary  = var.task_exec_iam_role_permissions_boundary
  force_detach_policies = true

  tags = merge(var.tags, var.task_exec_iam_role_tags)
}

resource "aws_iam_role_policy_attachment" "task_exec_additional" {
  for_each = { for k, v in var.task_exec_iam_role_policies : k => v if local.create_task_exec_iam_role }

  role       = aws_iam_role.task_exec[0].name
  policy_arn = each.value
}

data "aws_iam_policy_document" "task_exec" {
  count = local.create_task_exec_policy ? 1 : 0

  statement {
    sid = "Logs"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = ["arn:${local.partition}:logs:${local.region}:${local.account_id}:log-group:${local.log_group_name}:*"]
  }

  statement {
    sid = "ECR"
    actions = [
      "ecr:GetAuthorizationToken",
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
    ]
    resources = ["*"]
  }

  dynamic "statement" {
    for_each = length(var.task_exec_ssm_param_arns) > 0 ? [1] : []

    content {
      sid       = "GetSSMParams"
      actions   = ["ssm:GetParameters"]
      resources = var.task_exec_ssm_param_arns
    }
  }

  dynamic "statement" {
    for_each = length(var.task_exec_secret_arns) > 0 ? [1] : []

    content {
      sid       = "GetSecrets"
      actions   = ["secretsmanager:GetSecretValue"]
      resources = var.task_exec_secret_arns
    }
  }

  dynamic "statement" {
    for_each = var.task_exec_iam_statements != null ? var.task_exec_iam_statements : {}

    content {
      sid           = try(coalesce(statement.value.sid, statement.key))
      actions       = statement.value.actions
      not_actions   = statement.value.not_actions
      effect        = statement.value.effect
      resources     = statement.value.resources
      not_resources = statement.value.not_resources

      dynamic "principals" {
        for_each = statement.value.principals != null ? statement.value.principals : []

        content {
          type        = principals.value.type
          identifiers = principals.value.identifiers
        }
      }

      dynamic "not_principals" {
        for_each = statement.value.not_principals != null ? statement.value.not_principals : []

        content {
          type        = not_principals.value.type
          identifiers = not_principals.value.identifiers
        }
      }

      dynamic "condition" {
        for_each = statement.value.condition != null ? statement.value.condition : []

        content {
          test     = condition.value.test
          values   = condition.value.values
          variable = condition.value.variable
        }
      }
    }
  }
}

resource "aws_iam_policy" "task_exec" {
  count = local.create_task_exec_policy ? 1 : 0

  name        = var.task_exec_iam_role_use_name_prefix ? null : local.task_exec_iam_role_name
  name_prefix = var.task_exec_iam_role_use_name_prefix ? "${local.task_exec_iam_role_name}-" : null
  description = coalesce(var.task_exec_iam_role_description, "Task execution role IAM policy")
  policy      = data.aws_iam_policy_document.task_exec[0].json

  tags = merge(var.tags, var.task_exec_iam_role_tags)
}

resource "aws_iam_role_policy_attachment" "task_exec" {
  count = local.create_task_exec_policy ? 1 : 0

  role       = aws_iam_role.task_exec[0].name
  policy_arn = aws_iam_policy.task_exec[0].arn
}

################################################################################
# Infrastructure IAM role
################################################################################

locals {
  create_infrastructure_iam_role = var.create && var.create_infrastructure_iam_role && local.managed_instances_enabled

  infrastructure_iam_role_name = coalesce(var.infrastructure_iam_role_name, "${var.name}-infra")
}

data "aws_iam_policy_document" "infrastructure_assume" {
  count = local.create_infrastructure_iam_role ? 1 : 0

  statement {
    sid = "ECSServiceAssumeRole"
    actions = [
      "sts:AssumeRole",
      "sts:TagSession",
    ]

    principals {
      type        = "Service"
      identifiers = ["ecs.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "infrastructure" {
  count = local.create_infrastructure_iam_role ? 1 : 0

  name        = var.infrastructure_iam_role_use_name_prefix ? null : local.infrastructure_iam_role_name
  name_prefix = var.infrastructure_iam_role_use_name_prefix ? "${local.infrastructure_iam_role_name}-" : null
  path        = var.infrastructure_iam_role_path
  description = coalesce(var.infrastructure_iam_role_description, "Amazon ECS infrastructure IAM role that is used to manage your infrastructure (managed instances)")

  assume_role_policy    = data.aws_iam_policy_document.infrastructure_assume[0].json
  permissions_boundary  = var.infrastructure_iam_role_permissions_boundary
  force_detach_policies = true

  tags = merge(var.tags, var.infrastructure_iam_role_tags)
}

data "aws_iam_policy_document" "infrastructure" {
  count = local.create_infrastructure_iam_role ? 1 : 0

  source_policy_documents   = var.infrastructure_iam_role_source_policy_documents
  override_policy_documents = var.infrastructure_iam_role_override_policy_documents

  statement {
    sid       = "CreateLaunchTemplateForManagedInstances"
    actions   = ["ec2:CreateLaunchTemplate"]
    resources = ["arn:${local.partition}:ec2:${local.region}:${local.account_id}:launch-template/*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/AmazonECSManaged"
      values   = [true]
    }
  }

  statement {
    sid = "CreateLaunchTemplateVersionsForManagedInstances"
    actions = [
      "ec2:CreateLaunchTemplateVersion",
      "ec2:ModifyLaunchTemplate",
    ]
    resources = ["arn:${local.partition}:ec2:${local.region}:${local.account_id}:launch-template/*"]

    condition {
      test     = "StringEquals"
      variable = "ec2:ManagedResourceOperator"
      values   = ["ecs.amazonaws.com"]
    }
  }

  statement {
    sid     = "ProvisionEC2InstancesForManagedInstances"
    actions = ["ec2:CreateFleet"]
    resources = [
      "arn:${local.partition}:ec2:${local.region}:*:fleet/*",
      "arn:${local.partition}:ec2:${local.region}:*:instance/*",
      "arn:${local.partition}:ec2:${local.region}:*:network-interface/*",
      "arn:${local.partition}:ec2:${local.region}:*:launch-template/*",
      "arn:${local.partition}:ec2:${local.region}:*:volume/*",
    ]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/AmazonECSManaged"
      values   = [true]
    }
  }

  statement {
    sid     = "CreateFleetForSupportingResources"
    actions = ["ec2:CreateFleet"]
    resources = [
      "arn:${local.partition}:ec2:${local.region}:*:subnet/*",
      "arn:${local.partition}:ec2:${local.region}:*:security-group/*",
      "arn:${local.partition}:ec2:${local.region}:*:image/*",
    ]
  }

  statement {
    sid     = "RunInstancesForManagedInstances"
    actions = ["ec2:RunInstances"]
    resources = [
      "arn:${local.partition}:ec2:${local.region}:*:instance/*",
      "arn:${local.partition}:ec2:${local.region}:*:volume/*",
      "arn:${local.partition}:ec2:${local.region}:*:network-interface/*",
    ]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/AmazonECSManaged"
      values   = [true]
    }
  }

  statement {
    sid       = "RunInstancesForECSManagedLaunchTemplates"
    actions   = ["ec2:RunInstances"]
    resources = ["arn:${local.partition}:ec2:${local.region}:*:launch-template/*"]

    condition {
      test     = "StringEquals"
      variable = "ec2:ResourceTag/AmazonECSManaged"
      values   = [true]
    }
  }

  statement {
    sid     = "RunInstancesForSupportingResources"
    actions = ["ec2:RunInstances"]
    resources = [
      "arn:${local.partition}:ec2:${local.region}:*:subnet/*",
      "arn:${local.partition}:ec2:${local.region}:*:security-group/*",
      "arn:${local.partition}:ec2:${local.region}:*:image/*",
    ]
  }

  statement {
    sid     = "TagOnCreateEC2ResourcesForManagedInstances"
    actions = ["ec2:CreateTags"]
    resources = [
      "arn:${local.partition}:ec2:${local.region}:*:fleet/*",
      "arn:${local.partition}:ec2:${local.region}:*:launch-template/*",
      "arn:${local.partition}:ec2:${local.region}:*:network-interface/*",
      "arn:${local.partition}:ec2:${local.region}:*:instance/*",
      "arn:${local.partition}:ec2:${local.region}:*:volume/*",
    ]

    condition {
      test     = "StringEquals"
      variable = "ec2:CreateAction"
      values = [
        "CreateFleet",
        "CreateLaunchTemplate",
        "RunInstances",
      ]
    }
  }

  statement {
    sid       = "PassInstanceRoleForManagedInstances"
    actions   = ["iam:PassRole"]
    resources = [aws_iam_role.node[0].arn]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ec2.amazonaws.com"]
    }
  }

  statement {
    sid       = "CreateServiceLinkedRoleForEC2Spot"
    actions   = ["iam:CreateServiceLinkedRole"]
    resources = ["arn:${local.partition}:iam::${local.account_id}:role/aws-service-role/spot.amazonaws.com/AWSServiceRoleForEC2Spot"]
  }

  statement {
    sid = "DescribeEC2ResourcesManagedByECS"
    actions = [
      "ec2:DescribeInstances",
      "ec2:DescribeInstanceTypes",
      "ec2:DescribeLaunchTemplates",
      "ec2:DescribeNetworkInterfaces",
      "ec2:DescribeInstanceTypeOfferings",
      "ec2:DescribeAvailabilityZones",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeSubnets",
      "ec2:DescribeVpcs",
    ]
    resources = ["*"]
  }

  dynamic "statement" {
    for_each = var.infrastructure_iam_role_statements != null ? var.infrastructure_iam_role_statements : {}

    content {
      sid           = try(coalesce(statement.value.sid, statement.key))
      actions       = statement.value.actions
      not_actions   = statement.value.not_actions
      effect        = statement.value.effect
      resources     = statement.value.resources
      not_resources = statement.value.not_resources

      dynamic "principals" {
        for_each = statement.value.principals != null ? statement.value.principals : []

        content {
          type        = principals.value.type
          identifiers = principals.value.identifiers
        }
      }

      dynamic "not_principals" {
        for_each = statement.value.not_principals != null ? statement.value.not_principals : []

        content {
          type        = not_principals.value.type
          identifiers = not_principals.value.identifiers
        }
      }

      dynamic "condition" {
        for_each = statement.value.condition != null ? statement.value.condition : []

        content {
          test     = condition.value.test
          values   = condition.value.values
          variable = condition.value.variable
        }
      }
    }
  }
}

resource "aws_iam_policy" "infrastructure" {
  count = local.create_infrastructure_iam_role ? 1 : 0

  name        = var.infrastructure_iam_role_use_name_prefix ? null : local.infrastructure_iam_role_name
  name_prefix = var.infrastructure_iam_role_use_name_prefix ? "${local.infrastructure_iam_role_name}-" : null
  description = coalesce(var.infrastructure_iam_role_description, "ECS Managed Instances infrastructure role permissions")
  policy      = data.aws_iam_policy_document.infrastructure[0].json

  tags = merge(var.tags, var.infrastructure_iam_role_tags)
}

resource "aws_iam_role_policy_attachment" "infrastructure" {
  count = local.create_infrastructure_iam_role ? 1 : 0

  policy_arn = aws_iam_policy.infrastructure[0].arn
  role       = aws_iam_role.infrastructure[0].name
}

################################################################################
# Node IAM role
################################################################################

locals {
  create_node_iam_instance_profile = var.create && var.create_node_iam_instance_profile && local.managed_instances_enabled

  node_iam_role_name = coalesce(var.node_iam_role_name, "${var.name}-node")
}

data "aws_iam_policy_document" "node_assume_role_policy" {
  count = local.create_node_iam_instance_profile ? 1 : 0

  statement {
    sid = "ECSNodeAssumeRole"
    actions = [
      "sts:AssumeRole",
      "sts:TagSession",
    ]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "node" {
  count = local.create_node_iam_instance_profile ? 1 : 0

  name        = var.node_iam_role_use_name_prefix ? null : local.node_iam_role_name
  name_prefix = var.node_iam_role_use_name_prefix ? "${local.node_iam_role_name}-" : null
  path        = var.node_iam_role_path
  description = coalesce(var.node_iam_role_description, "Amazon ECS managed instance node role for ECS cluster ${var.name}")

  assume_role_policy    = data.aws_iam_policy_document.node_assume_role_policy[0].json
  permissions_boundary  = var.node_iam_role_permissions_boundary
  force_detach_policies = true

  tags = merge(var.tags, var.node_iam_role_tags)
}

resource "aws_iam_role_policy_attachment" "node_additional" {
  for_each = { for k, v in var.node_iam_role_additional_policies : k => v if local.create_node_iam_instance_profile }

  policy_arn = each.value
  role       = aws_iam_role.node[0].name
}

data "aws_iam_policy_document" "node" {
  count = local.create_node_iam_instance_profile ? 1 : 0

  source_policy_documents   = var.node_iam_role_source_policy_documents
  override_policy_documents = var.node_iam_role_override_policy_documents

  statement {
    sid       = "ECSAgentDiscoverPollEndpointPermissions"
    actions   = ["ecs:DiscoverPollEndpoint"]
    resources = ["*"]
  }

  statement {
    sid       = "ECSAgentRegisterPermissions"
    actions   = ["ecs:RegisterContainerInstance"]
    resources = [aws_ecs_cluster.this[0].arn]
  }

  statement {
    sid       = "ECSAgentPollPermissions"
    actions   = ["ecs:Poll"]
    resources = ["arn:${local.partition}:ecs:${local.region}:${local.account_id}:container-instance/*"]
  }

  statement {
    sid = "ECSAgentTelemetryPermissions"
    actions = [
      "ecs:StartTelemetrySession",
      "ecs:PutSystemLogEvents",
    ]
    resources = ["arn:${local.partition}:ecs:${local.region}:${local.account_id}:container-instance/*"]
  }

  statement {
    sid = "ECSAgentStateChangePermissions"
    actions = [
      "ecs:SubmitAttachmentStateChanges",
      "ecs:SubmitTaskStateChange",
    ]
    resources = [aws_ecs_cluster.this[0].arn]
  }

  dynamic "statement" {
    for_each = var.node_iam_role_statements != null ? var.node_iam_role_statements : {}

    content {
      sid           = try(coalesce(statement.value.sid, statement.key))
      actions       = statement.value.actions
      not_actions   = statement.value.not_actions
      effect        = statement.value.effect
      resources     = statement.value.resources
      not_resources = statement.value.not_resources

      dynamic "principals" {
        for_each = statement.value.principals != null ? statement.value.principals : []

        content {
          type        = principals.value.type
          identifiers = principals.value.identifiers
        }
      }

      dynamic "not_principals" {
        for_each = statement.value.not_principals != null ? statement.value.not_principals : []

        content {
          type        = not_principals.value.type
          identifiers = not_principals.value.identifiers
        }
      }

      dynamic "condition" {
        for_each = statement.value.condition != null ? statement.value.condition : []

        content {
          test     = condition.value.test
          values   = condition.value.values
          variable = condition.value.variable
        }
      }
    }
  }
}

resource "aws_iam_policy" "node" {
  count = local.create_node_iam_instance_profile ? 1 : 0

  name        = var.node_iam_role_use_name_prefix ? null : local.node_iam_role_name
  name_prefix = var.node_iam_role_use_name_prefix ? "${local.node_iam_role_name}-" : null
  description = coalesce(var.node_iam_role_description, "ECS Managed Instances permissions")
  policy      = data.aws_iam_policy_document.node[0].json

  tags = merge(var.tags, var.node_iam_role_tags)
}

resource "aws_iam_role_policy_attachment" "node" {
  count = local.create_node_iam_instance_profile ? 1 : 0

  policy_arn = aws_iam_policy.node[0].arn
  role       = aws_iam_role.node[0].name
}

################################################################################
# Node Instance Profile
################################################################################

resource "aws_iam_instance_profile" "this" {
  count = local.create_node_iam_instance_profile ? 1 : 0

  role = aws_iam_role.node[0].name

  name        = var.node_iam_role_use_name_prefix ? null : local.node_iam_role_name
  name_prefix = var.node_iam_role_use_name_prefix ? "${local.node_iam_role_name}-" : null
  path        = var.node_iam_role_path

  tags = merge(var.tags, var.node_iam_role_tags)

  lifecycle {
    create_before_destroy = true
  }
}

################################################################################
# Security Group
################################################################################

locals {
  create_security_group = var.create && var.create_security_group && local.managed_instances_enabled

  security_group_name = coalesce(var.security_group_name, "${var.name}${var.disable_v7_default_name_description ? "" : "-cluster"}")
}

resource "aws_security_group" "this" {
  count = local.create_security_group ? 1 : 0

  region = var.region

  name        = var.security_group_use_name_prefix ? null : local.security_group_name
  name_prefix = var.security_group_use_name_prefix ? "${local.security_group_name}-" : null
  description = coalesce(var.security_group_description, "Security group for ECS managed instances in cluster ${aws_ecs_cluster.this[0].name}")
  vpc_id      = var.vpc_id

  tags = merge(
    var.tags,
    { Name = local.security_group_name },
    var.security_group_tags
  )

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "this" {
  for_each = { for k, v in var.security_group_ingress_rules : k => v if var.security_group_ingress_rules != null && local.create_security_group }

  region = var.region

  cidr_ipv4                    = each.value.cidr_ipv4
  cidr_ipv6                    = each.value.cidr_ipv6
  description                  = each.value.description
  from_port                    = each.value.from_port
  ip_protocol                  = each.value.ip_protocol
  prefix_list_id               = each.value.prefix_list_id
  referenced_security_group_id = each.value.referenced_security_group_id == "self" ? aws_security_group.this[0].id : each.value.referenced_security_group_id
  security_group_id            = aws_security_group.this[0].id
  tags = merge(
    var.tags,
    var.security_group_tags,
    { "Name" = coalesce(each.value.name, "${local.security_group_name}-${each.key}") },
    each.value.tags
  )
  to_port = try(coalesce(each.value.to_port, each.value.from_port), null)
}

resource "aws_vpc_security_group_egress_rule" "this" {
  for_each = { for k, v in var.security_group_egress_rules : k => v if var.security_group_egress_rules != null && local.create_security_group }

  region = var.region

  cidr_ipv4                    = each.value.cidr_ipv4
  cidr_ipv6                    = each.value.cidr_ipv6
  description                  = each.value.description
  from_port                    = try(coalesce(each.value.from_port, each.value.to_port), null)
  ip_protocol                  = each.value.ip_protocol
  prefix_list_id               = each.value.prefix_list_id
  referenced_security_group_id = each.value.referenced_security_group_id == "self" ? aws_security_group.this[0].id : each.value.referenced_security_group_id
  security_group_id            = aws_security_group.this[0].id
  tags = merge(
    var.tags,
    var.security_group_tags,
    { "Name" = coalesce(each.value.name, "${local.security_group_name}-${each.key}") },
    each.value.tags
  )
  to_port = each.value.to_port
}

################################################################################
# Outputs
################################################################################

output "arn" {
  description = "ARN that identifies the cluster"
  value       = try(aws_ecs_cluster.this[0].arn, null)
}

output "id" {
  description = "ID that identifies the cluster"
  value       = try(aws_ecs_cluster.this[0].id, null)
}

output "name" {
  description = "Name that identifies the cluster"
  value       = try(aws_ecs_cluster.this[0].name, null)
}

output "cloudwatch_log_group_name" {
  description = "Name of CloudWatch log group created"
  value       = try(aws_cloudwatch_log_group.this[0].name, null)
}

output "cloudwatch_log_group_arn" {
  description = "ARN of CloudWatch log group created"
  value       = try(aws_cloudwatch_log_group.this[0].arn, null)
}

output "cluster_capacity_providers" {
  description = "Map of cluster capacity providers attributes"
  value       = { for k, v in aws_ecs_cluster_capacity_providers.this : v.id => v }
}

output "capacity_providers" {
  description = "Map of autoscaling capacity providers created and their attributes"
  value       = var.capacity_providers != null ? jsondecode(time_sleep.this[0].triggers["capacity_providers"]) : {}
}

output "task_exec_iam_role_arn" {
  description = "The Amazon Resource Name (ARN) specifying the IAM role"
  value       = try(aws_iam_role.task_exec[0].arn, null)
}

output "task_exec_iam_role_name" {
  description = "IAM role name"
  value       = try(aws_iam_role.task_exec[0].name, null)
}

output "task_exec_iam_role_unique_id" {
  description = "Stable and unique string identifying the IAM role"
  value       = try(aws_iam_role.task_exec[0].unique_id, null)
}

output "infrastructure_iam_role_arn" {
  description = "The Amazon Resource Name (ARN) specifying the IAM role"
  value       = try(aws_iam_role.infrastructure[0].arn, null)
}

output "infrastructure_iam_role_name" {
  description = "IAM role name"
  value       = try(aws_iam_role.infrastructure[0].name, null)
}

output "infrastructure_iam_role_unique_id" {
  description = "Stable and unique string identifying the IAM role"
  value       = try(aws_iam_role.infrastructure[0].unique_id, null)
}

output "node_iam_role_arn" {
  description = "The Amazon Resource Name (ARN) specifying the IAM role"
  value       = try(aws_iam_role.node[0].arn, null)
}

output "node_iam_role_name" {
  description = "IAM role name"
  value       = try(aws_iam_role.node[0].name, null)
}

output "node_iam_role_unique_id" {
  description = "Stable and unique string identifying the IAM role"
  value       = try(aws_iam_role.node[0].unique_id, null)
}

output "node_iam_instance_profile_arn" {
  description = "ARN assigned by AWS to the instance profile"
  value       = try(aws_iam_instance_profile.this[0].arn, null)
}

output "node_iam_instance_profile_id" {
  description = "Instance profile's ID"
  value       = try(aws_iam_instance_profile.this[0].id, null)
}

output "node_iam_instance_profile_unique" {
  description = "Stable and unique string identifying the IAM instance profile"
  value       = try(aws_iam_instance_profile.this[0].unique_id, null)
}

output "security_group_id" {
  description = "The ID of the security group"
  value       = try(aws_security_group.this[0].id, null)
}

################################################################################
# Variables
################################################################################

variable "create" {
  description = "Determines whether resources will be created (affects all resources)"
  type        = bool
  default     = true
}

variable "region" {
  description = "Region where the resource(s) will be managed. Defaults to the Region set in the provider configuration"
  type        = string
  default     = null
}

variable "tags" {
  description = "A map of tags to add to all resources"
  type        = map(string)
  default     = {}
}

variable "disable_v7_default_name_description" {
  description = "[DEPRECATED - will be removed in v8.0] Determines whether to disable the default postfix added to resource names and descriptions added in v7.0"
  type        = bool
  default     = false
}

variable "configuration" {
  description = "The execute command configuration for the cluster"
  type = object({
    execute_command_configuration = optional(object({
      kms_key_id = optional(string)
      log_configuration = optional(object({
        cloud_watch_encryption_enabled = optional(bool)
        cloud_watch_log_group_name     = optional(string)
        s3_bucket_encryption_enabled   = optional(bool)
        s3_bucket_name                 = optional(string)
        s3_kms_key_id                  = optional(string)
        s3_key_prefix                  = optional(string)
      }))
      logging = optional(string, "OVERRIDE")
    }))
    managed_storage_configuration = optional(object({
      fargate_ephemeral_storage_kms_key_id = optional(string)
      kms_key_id                           = optional(string)
    }))
  })
  default = {
    execute_command_configuration = {
      log_configuration = {
        cloud_watch_log_group_name = "placeholder"
      }
    }
  }
}

variable "name" {
  description = "Name of the cluster (up to 255 letters, numbers, hyphens, and underscores)"
  type        = string
  default     = ""
}

variable "service_connect_defaults" {
  description = "Configures a default Service Connect namespace"
  type = object({
    namespace = string
  })
  default = null
}

variable "setting" {
  description = "List of configuration block(s) with cluster settings. For example, this can be used to enable CloudWatch Container Insights for a cluster"
  type = list(object({
    name  = string
    value = string
  }))
  default = [
    {
      name  = "containerInsights"
      value = "enabled"
    }
  ]
}

variable "create_cloudwatch_log_group" {
  description = "Determines whether a log group is created by this module for the cluster logs. If not, AWS will automatically create one if logging is enabled"
  type        = bool
  default     = true
}

variable "cloudwatch_log_group_name" {
  description = "Custom name of CloudWatch Log Group for ECS cluster"
  type        = string
  default     = null
}

variable "cloudwatch_log_group_retention_in_days" {
  description = "Number of days to retain log events"
  type        = number
  default     = 365
}

variable "cloudwatch_log_group_kms_key_id" {
  description = "If a KMS Key ARN is set, this key will be used to encrypt the corresponding log group. Please be sure that the KMS Key has an appropriate key policy (https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/encrypt-log-data-kms.html)"
  type        = string
  default     = null
}

variable "cloudwatch_log_group_class" {
  description = "Specified the log class of the log group. Possible values are: `STANDARD` or `INFREQUENT_ACCESS`"
  type        = string
  default     = null
}

variable "cloudwatch_log_group_tags" {
  description = "A map of additional tags to add to the log group created"
  type        = map(string)
  default     = {}
}

variable "cluster_capacity_providers_wait_duration" {
  description = "Duration to wait after the ECS cluster has become active before attaching the cluster capacity providers"
  type        = string
  default     = "20s"
}

variable "cluster_capacity_providers" {
  description = "List of capacity provider names to associate with the ECS cluster. Note: any capacity providers created by this module will be automatically added"
  type        = list(string)
  default     = []
}

variable "capacity_providers" {
  description = "Map of capacity provider definitions to create"
  type = map(object({
    auto_scaling_group_provider = optional(object({
      auto_scaling_group_arn = string
      managed_draining       = optional(string, "ENABLED")
      managed_scaling = optional(object({
        instance_warmup_period    = optional(number)
        maximum_scaling_step_size = optional(number)
        minimum_scaling_step_size = optional(number)
        status                    = optional(string)
        target_capacity           = optional(number)
      }))
      managed_termination_protection = optional(string)
    }))
    managed_instances_provider = optional(object({
      infrastructure_role_arn = optional(string)
      instance_launch_template = object({
        capacity_option_type     = optional(string)
        ec2_instance_profile_arn = optional(string)
        instance_requirements = optional(object({
          accelerator_count = optional(object({
            max = optional(number)
            min = optional(number)
          }))
          accelerator_manufacturers = optional(list(string))
          accelerator_names         = optional(list(string))
          accelerator_total_memory_mib = optional(object({
            max = optional(number)
            min = optional(number)
          }))
          accelerator_types      = optional(list(string))
          allowed_instance_types = optional(list(string))
          bare_metal             = optional(string)
          baseline_ebs_bandwidth_mbps = optional(object({
            max = optional(number)
            min = optional(number)
          }))
          burstable_performance                                   = optional(string)
          cpu_manufacturers                                       = optional(list(string))
          excluded_instance_types                                 = optional(list(string))
          instance_generations                                    = optional(list(string))
          local_storage                                           = optional(string)
          local_storage_types                                     = optional(list(string))
          max_spot_price_as_percentage_of_optimal_on_demand_price = optional(number)
          memory_gib_per_vcpu = optional(object({
            max = optional(number)
            min = optional(number)
          }))
          memory_mib = optional(object({
            max = optional(number)
            min = optional(number)
          }))
          network_bandwidth_gbps = optional(object({
            max = optional(number)
            min = optional(number)
          }))
          network_interface_count = optional(object({
            max = optional(number)
            min = optional(number)
          }))
          on_demand_max_price_percentage_over_lowest_price = optional(number)
          require_hibernate_support                        = optional(bool)
          spot_max_price_percentage_over_lowest_price      = optional(number)
          total_local_storage_gb = optional(object({
            max = optional(number)
            min = optional(number)
          }))
          vcpu_count = optional(object({
            max = optional(number)
            min = optional(number)
          }))
        }))
        monitoring = optional(string)
        network_configuration = optional(object({
          security_groups = optional(list(string), [])
          subnets         = list(string)
        }))
        storage_configuration = optional(object({
          storage_size_gib = number
        }))
      })
      propagate_tags = optional(string, "CAPACITY_PROVIDER")
    }))
    name = optional(string)
    tags = optional(map(string), {})
  }))
  default = null
}

variable "default_capacity_provider_strategy" {
  description = "Map of default capacity provider strategy definitions to use for the cluster"
  type = map(object({
    base   = optional(number)
    name   = optional(string)
    weight = optional(number)
  }))
  default  = {}
  nullable = false
}

variable "create_task_exec_iam_role" {
  description = "Determines whether the ECS task definition IAM role should be created"
  type        = bool
  default     = false
}

variable "task_exec_iam_role_name" {
  description = "Name to use on IAM role created"
  type        = string
  default     = null
}

variable "task_exec_iam_role_use_name_prefix" {
  description = "Determines whether the IAM role name (`task_exec_iam_role_name`) is used as a prefix"
  type        = bool
  default     = true
}

variable "task_exec_iam_role_path" {
  description = "IAM role path"
  type        = string
  default     = null
}

variable "task_exec_iam_role_description" {
  description = "Description of the role"
  type        = string
  default     = null
}

variable "task_exec_iam_role_permissions_boundary" {
  description = "ARN of the policy that is used to set the permissions boundary for the IAM role"
  type        = string
  default     = null
}

variable "task_exec_iam_role_policies" {
  description = "Map of IAM role policy ARNs to attach to the IAM role"
  type        = map(string)
  default     = {}
}

variable "create_task_exec_policy" {
  description = "Determines whether the ECS task definition IAM policy should be created. This includes permissions included in AmazonECSTaskExecutionRolePolicy as well as access to secrets and SSM parameters"
  type        = bool
  default     = true
}

variable "task_exec_ssm_param_arns" {
  description = "List of SSM parameter ARNs the task execution role will be permitted to get/read"
  type        = list(string)
  default     = []
}

variable "task_exec_secret_arns" {
  description = "List of SecretsManager secret ARNs the task execution role will be permitted to get/read"
  type        = list(string)
  default     = []
}

variable "task_exec_iam_statements" {
  description = "A map of IAM policy [statements](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document#statement) for custom permission usage"
  type = map(object({
    sid           = optional(string)
    actions       = optional(list(string))
    not_actions   = optional(list(string))
    effect        = optional(string, "Allow")
    resources     = optional(list(string))
    not_resources = optional(list(string))
    principals = optional(list(object({
      type        = string
      identifiers = list(string)
    })))
    not_principals = optional(list(object({
      type        = string
      identifiers = list(string)
    })))
    condition = optional(list(object({
      test     = string
      variable = string
      values   = list(string)
    })))
  }))
  default = null
}

variable "create_infrastructure_iam_role" {
  description = "Determines whether the ECS infrastructure IAM role should be created"
  type        = bool
  default     = true
  nullable    = false
}

variable "infrastructure_iam_role_name" {
  description = "Name to use on IAM role created"
  type        = string
  default     = null
}

variable "infrastructure_iam_role_use_name_prefix" {
  description = "Determines whether the IAM role name (`iam_role_name`) is used as a prefix"
  type        = bool
  default     = true
  nullable    = false
}

variable "infrastructure_iam_role_path" {
  description = "IAM role path"
  type        = string
  default     = null
}

variable "infrastructure_iam_role_description" {
  description = "Description of the role"
  type        = string
  default     = null
}

variable "infrastructure_iam_role_permissions_boundary" {
  description = "ARN of the policy that is used to set the permissions boundary for the IAM role"
  type        = string
  default     = null
}

variable "infrastructure_iam_role_tags" {
  description = "A map of additional tags to add to the IAM role created"
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "infrastructure_iam_role_source_policy_documents" {
  description = "List of IAM policy documents that are merged together into the exported document. Statements must have unique `sid`s"
  type        = list(string)
  default     = []
}

variable "infrastructure_iam_role_override_policy_documents" {
  description = "List of IAM policy documents that are merged together into the exported document. In merging, statements with non-blank `sid`s will override statements with the same `sid`"
  type        = list(string)
  default     = []
}

variable "infrastructure_iam_role_statements" {
  description = "A map of IAM policy [statements](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document#statement) for custom permission usage"
  type = map(object({
    sid           = optional(string)
    actions       = optional(list(string))
    not_actions   = optional(list(string))
    effect        = optional(string, "Allow")
    resources     = optional(list(string))
    not_resources = optional(list(string))
    principals = optional(list(object({
      type        = string
      identifiers = list(string)
    })))
    not_principals = optional(list(object({
      type        = string
      identifiers = list(string)
    })))
    condition = optional(list(object({
      test     = string
      variable = string
      values   = list(string)
    })))
  }))
  default = null
}

variable "create_node_iam_instance_profile" {
  description = "Determines whether an IAM instance profile is created or to use an existing IAM instance profile"
  type        = bool
  default     = true
  nullable    = false
}

variable "node_iam_role_name" {
  description = "Name to use on IAM role/instance profile created"
  type        = string
  default     = null
}

variable "node_iam_role_use_name_prefix" {
  description = "Determines whether the IAM role/instance profile name (`node_iam_role_name`) is used as a prefix"
  type        = bool
  default     = true
  nullable    = false
}

variable "node_iam_role_path" {
  description = "IAM role/instance profile path"
  type        = string
  default     = null
}

variable "node_iam_role_description" {
  description = "Description of the role"
  type        = string
  default     = "ECS Managed Instances node IAM role"
  nullable    = false
}

variable "node_iam_role_permissions_boundary" {
  description = "ARN of the policy that is used to set the permissions boundary for the IAM role"
  type        = string
  default     = null
}

variable "node_iam_role_additional_policies" {
  description = "Additional policies to be added to the IAM role"
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "node_iam_role_tags" {
  description = "A map of additional tags to add to the IAM role/instance profile created"
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "node_iam_role_source_policy_documents" {
  description = "List of IAM policy documents that are merged together into the exported document. Statements must have unique `sid`s"
  type        = list(string)
  default     = []
}

variable "node_iam_role_override_policy_documents" {
  description = "List of IAM policy documents that are merged together into the exported document. In merging, statements with non-blank `sid`s will override statements with the same `sid`"
  type        = list(string)
  default     = []
}

variable "node_iam_role_statements" {
  description = "A map of IAM policy [statements](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document#statement) for custom permission usage"
  type = map(object({
    sid           = optional(string)
    actions       = optional(list(string))
    not_actions   = optional(list(string))
    effect        = optional(string, "Allow")
    resources     = optional(list(string))
    not_resources = optional(list(string))
    principals = optional(list(object({
      type        = string
      identifiers = list(string)
    })))
    not_principals = optional(list(object({
      type        = string
      identifiers = list(string)
    })))
    condition = optional(list(object({
      test     = string
      variable = string
      values   = list(string)
    })))
  }))
  default = null
}

variable "create_security_group" {
  description = "Determines if a security group is created"
  type        = bool
  default     = true
  nullable    = false
}

variable "vpc_id" {
  description = "The ID of the VPC where the security group will be created"
  type        = string
  default     = null
}

variable "security_group_name" {
  description = "Name to use on security group created"
  type        = string
  default     = null
}

variable "security_group_use_name_prefix" {
  description = "Determines whether the security group name (`security_group_name`) is used as a prefix"
  type        = bool
  default     = true
  nullable    = false
}

variable "security_group_description" {
  description = "Description of the security group created"
  type        = string
  default     = null
}

variable "security_group_ingress_rules" {
  description = "Security group ingress rules to add to the security group created"
  type = map(object({
    name = optional(string)

    cidr_ipv4                    = optional(string)
    cidr_ipv6                    = optional(string)
    description                  = optional(string)
    from_port                    = optional(string)
    ip_protocol                  = optional(string, "tcp")
    prefix_list_id               = optional(string)
    referenced_security_group_id = optional(string)
    tags                         = optional(map(string), {})
    to_port                      = optional(string)
  }))
  default  = {}
  nullable = false
}

variable "security_group_egress_rules" {
  description = "Security group egress rules to add to the security group created"
  type = map(object({
    name = optional(string)

    cidr_ipv4                    = optional(string)
    cidr_ipv6                    = optional(string)
    description                  = optional(string)
    from_port                    = optional(string)
    ip_protocol                  = optional(string, "tcp")
    prefix_list_id               = optional(string)
    referenced_security_group_id = optional(string)
    tags                         = optional(map(string), {})
    to_port                      = optional(string)
  }))
  default = {
    all_ipv4 = {
      cidr_ipv4   = "0.0.0.0/0"
      description = "Allow all IPv4 traffic"
      ip_protocol = "-1"
    }
    all_ipv6 = {
      cidr_ipv6   = "::/0"
      description = "Allow all IPv6 traffic"
      ip_protocol = "-1"
    }
  }
  nullable = false
}

variable "security_group_tags" {
  description = "A map of additional tags to add to the security group created"
  type        = map(string)
  default     = {}
  nullable    = false
}

terraform {
  required_version = ">= 1.5.7"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.34"
    }
    time = {
      source  = "hashicorp/time"
      version = ">= 0.13"
    }
  }

  provider_meta "aws" {
    user_agent = [
      "github.com/terraform-aws-modules/terraform-aws-ecs"
    ]
  }
}