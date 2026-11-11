```hcl
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
# Service
################################################################################

locals {
  # https://docs.aws.amazon.com/AmazonECS/latest/developerguide/deployment-type-external.html
  is_external_deployment = try(var.deployment_controller.type, null) == "EXTERNAL"
  is_daemon              = var.scheduling_strategy == "DAEMON"
  is_fargate             = var.launch_type == "FARGATE"

  # Flattened `network_configuration`
  network_configuration = {
    assign_public_ip = var.assign_public_ip
    security_groups  = flatten(concat([try(aws_security_group.this[0].id, [])], var.security_group_ids))
    subnets          = var.subnet_ids
  }

  create_service = var.create && var.create_service
}

resource "aws_ecs_service" "this" {
  count = local.create_service && !var.ignore_task_definition_changes ? 1 : 0

  region = var.region

  dynamic "alarms" {
    for_each = var.alarms != null ? [var.alarms] : []

    content {
      alarm_names = alarms.value.alarm_names
      enable      = alarms.value.enable
      rollback    = alarms.value.rollback
    }
  }

  availability_zone_rebalancing = var.availability_zone_rebalancing

  dynamic "capacity_provider_strategy" {
    # Set by task set if deployment controller is external
    for_each = !local.is_external_deployment && var.capacity_provider_strategy != null ? var.capacity_provider_strategy : {}

    content {
      base              = capacity_provider_strategy.value.base
      capacity_provider = capacity_provider_strategy.value.capacity_provider
      weight            = coalesce(capacity_provider_strategy.value.weight, 1)
    }
  }

  cluster = var.cluster_arn

  dynamic "deployment_circuit_breaker" {
    for_each = var.deployment_circuit_breaker != null ? [var.deployment_circuit_breaker] : []

    content {
      enable   = deployment_circuit_breaker.value.enable
      rollback = deployment_circuit_breaker.value.rollback
    }
  }

  dynamic "deployment_configuration" {
    for_each = var.deployment_configuration != null ? [var.deployment_configuration] : []

    content {
      strategy             = deployment_configuration.value.strategy
      bake_time_in_minutes = deployment_configuration.value.bake_time_in_minutes

      dynamic "linear_configuration" {
        for_each = deployment_configuration.value.linear_configuration != null ? [deployment_configuration.value.linear_configuration] : []

        content {
          step_bake_time_in_minutes = linear_configuration.value.step_bake_time_in_minutes
          step_percent              = linear_configuration.value.step_percent
        }
      }

      dynamic "canary_configuration" {
        for_each = deployment_configuration.value.canary_configuration != null ? [deployment_configuration.value.canary_configuration] : []

        content {
          canary_bake_time_in_minutes = canary_configuration.value.canary_bake_time_in_minutes
          canary_percent              = canary_configuration.value.canary_percent
        }
      }

      dynamic "lifecycle_hook" {
        for_each = deployment_configuration.value.lifecycle_hook != null ? deployment_configuration.value.lifecycle_hook : {}

        content {
          hook_target_arn  = lifecycle_hook.value.hook_target_arn
          role_arn         = try(coalesce(lifecycle_hook.value.role_arn, local.infrastructure_iam_role_arn))
          lifecycle_stages = lifecycle_hook.value.lifecycle_stages
          hook_details     = lifecycle_hook.value.hook_details
        }
      }
    }
  }

  dynamic "deployment_controller" {
    for_each = var.deployment_controller != null ? [var.deployment_controller] : []

    content {
      type = deployment_controller.value.type
    }
  }

  deployment_maximum_percent         = local.is_daemon || local.is_external_deployment ? null : var.deployment_maximum_percent
  deployment_minimum_healthy_percent = local.is_daemon || local.is_external_deployment ? null : var.deployment_minimum_healthy_percent
  desired_count                      = local.is_daemon || local.is_external_deployment ? null : var.desired_count
  enable_ecs_managed_tags            = var.enable_ecs_managed_tags
  enable_execute_command             = var.enable_execute_command
  force_delete                       = var.force_delete
  force_new_deployment               = local.is_external_deployment ? null : var.force_new_deployment
  health_check_grace_period_seconds  = var.health_check_grace_period_seconds
  iam_role                           = local.iam_role_arn
  launch_type                        = local.is_external_deployment || var.capacity_provider_strategy != null ? null : var.launch_type

  dynamic "load_balancer" {
    # Set by task set if deployment controller is external
    for_each = var.load_balancer != null ? var.load_balancer : {}

    content {
      container_name   = load_balancer.value.container_name
      container_port   = load_balancer.value.container_port
      elb_name         = load_balancer.value.elb_name
      target_group_arn = load_balancer.value.target_group_arn

      dynamic "advanced_configuration" {
        for_each = load_balancer.value.advanced_configuration != null ? [load_balancer.value.advanced_configuration] : []

        content {
          alternate_target_group_arn = advanced_configuration.value.alternate_target_group_arn
          production_listener_rule   = advanced_configuration.value.production_listener_rule
          role_arn                   = try(coalesce(advanced_configuration.value.role_arn, local.infrastructure_iam_role_arn))
          test_listener_rule         = advanced_configuration.value.test_listener_rule
        }
      }
    }
  }

  name = var.name

  dynamic "network_configuration" {
    # Set by task set if deployment controller is external
    for_each = var.network_mode == "awsvpc" && !local.is_external_deployment ? [local.network_configuration] : []

    content {
      assign_public_ip = network_configuration.value.assign_public_ip
      security_groups  = network_configuration.value.security_groups
      subnets          = network_configuration.value.subnets
    }
  }

  dynamic "ordered_placement_strategy" {
    for_each = var.ordered_placement_strategy != null ? var.ordered_placement_strategy : []

    content {
      field = ordered_placement_strategy.value.field
      type  = ordered_placement_strategy.value.type
    }
  }

  dynamic "placement_constraints" {
    for_each = var.placement_constraints != null ? var.placement_constraints : {}

    content {
      expression = placement_constraints.value.expression
      type       = placement_constraints.value.type
    }
  }

  # Set by task set if deployment controller is external
  platform_version    = local.is_fargate && !local.is_external_deployment ? var.platform_version : null
  propagate_tags      = var.propagate_tags
  scheduling_strategy = local.is_fargate ? "REPLICA" : var.scheduling_strategy

  dynamic "service_connect_configuration" {
    for_each = var.service_connect_configuration != null ? [var.service_connect_configuration] : []

    content {
      enabled = service_connect_configuration.value.enabled

      dynamic "access_log_configuration" {
        for_each = service_connect_configuration.value.access_log_configuration != null ? [service_connect_configuration.value.access_log_configuration] : []

        content {
          format                   = access_log_configuration.value.format
          include_query_parameters = access_log_configuration.value.include_query_parameters
        }
      }

      dynamic "log_configuration" {
        for_each = service_connect_configuration.value.log_configuration != null ? [service_connect_configuration.value.log_configuration] : []

        content {
          log_driver = log_configuration.value.log_driver
          options    = log_configuration.value.options

          dynamic "secret_option" {
            for_each = log_configuration.value.secret_option != null ? log_configuration.value.secret_option : []

            content {
              name       = secret_option.value.name
              value_from = secret_option.value.value_from
            }
          }
        }
      }

      namespace = service_connect_configuration.value.namespace

      dynamic "service" {
        for_each = service_connect_configuration.value.service != null ? service_connect_configuration.value.service : []

        content {
          dynamic "client_alias" {
            for_each = service.value.client_alias != null ? [service.value.client_alias] : []

            content {
              dns_name = client_alias.value.dns_name
              port     = client_alias.value.port

              dynamic "test_traffic_rules" {
                for_each = client_alias.value.test_traffic_rules != null ? client_alias.value.test_traffic_rules : []

                content {
                  dynamic "header" {
                    for_each = test_traffic_rules.value.header != null ? [test_traffic_rules.value.header] : []

                    content {
                      name = header.value.name

                      dynamic "value" {
                        for_each = header.value.value != null ? [header.value.value] : []

                        content {
                          exact = value.value.exact
                        }
                      }
                    }
                  }
                }
              }
            }
          }

          discovery_name        = service.value.discovery_name
          ingress_port_override = service.value.ingress_port_override
          port_name             = service.value.port_name

          dynamic "timeout" {
            for_each = service.value.timeout != null ? [service.value.timeout] : []

            content {
              idle_timeout_seconds        = timeout.value.idle_timeout_seconds
              per_request_timeout_seconds = timeout.value.per_request_timeout_seconds
            }
          }

          dynamic "tls" {
            for_each = service.value.tls != null ? [service.value.tls] : []

            content {
              dynamic "issuer_cert_authority" {
                for_each = [tls.value.issuer_cert_authority]

                content {
                  aws_pca_authority_arn = issuer_cert_authority.value.aws_pca_authority_arn
                }
              }

              kms_key  = tls.value.kms_key
              role_arn = tls.value.role_arn
            }
          }
        }
      }
    }
  }

  dynamic "service_registries" {
    # Set by task set if deployment controller is external
    for_each = var.service_registries != null && !local.is_external_deployment ? [var.service_registries] : []

    content {
      container_name = service_registries.value.container_name
      container_port = service_registries.value.container_port
      port           = service_registries.value.port
      registry_arn   = service_registries.value.registry_arn
    }
  }

  sigint_rollback = try(var.deployment_configuration.strategy, null) == "BLUE_GREEN" ? var.sigint_rollback : null

  tags            = merge(var.tags, var.service_tags)
  task_definition = local.task_definition
  triggers        = var.triggers

  dynamic "volume_configuration" {
    for_each = var.volume_configuration != null ? [var.volume_configuration] : []

    content {
      name = try(volume_configuration.value.name, volume_configuration.key)

      dynamic "managed_ebs_volume" {
        for_each = [volume_configuration.value.managed_ebs_volume]

        content {
          encrypted        = managed_ebs_volume.value.encrypted
          file_system_type = managed_ebs_volume.value.file_system_type
          iops             = managed_ebs_volume.value.iops
          kms_key_id       = managed_ebs_volume.value.kms_key_id
          role_arn         = local.infrastructure_iam_role_arn
          size_in_gb       = managed_ebs_volume.value.size_in_gb
          snapshot_id      = managed_ebs_volume.value.snapshot_id

          dynamic "tag_specifications" {
            for_each = managed_ebs_volume.value.tag_specifications != null ? managed_ebs_volume.value.tag_specifications : []

            content {
              resource_type  = tag_specifications.value.resource_type
              propagate_tags = tag_specifications.value.propagate_tags
              tags           = tag_specifications.value.tags
            }
          }

          throughput  = managed_ebs_volume.value.throughput
          volume_type = managed_ebs_volume.value.volume_type
        }
      }
    }
  }

  dynamic "vpc_lattice_configurations" {
    for_each = var.vpc_lattice_configurations != null ? [var.vpc_lattice_configurations] : []

    content {
      role_arn         = local.infrastructure_iam_role_arn
      target_group_arn = vpc_lattice_configurations.value.target_group_arn
      port_name        = vpc_lattice_configurations.value.port_name
    }
  }

  wait_for_steady_state = var.wait_for_steady_state

  dynamic "timeouts" {
    for_each = var.timeouts != null ? [var.timeouts] : []

    content {
      create = timeouts.value.create
      update = timeouts.value.update
      delete = timeouts.value.delete
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.service,
    aws_iam_role_policy_attachment.infrastructure_iam_role_ebs_policy,
    aws_vpc_security_group_ingress_rule.this,
    aws_vpc_security_group_egress_rule.this,
  ]

  lifecycle {
    ignore_changes = [
      desired_count, # Always ignored
    ]
  }
}

################################################################################
# Service - Ignore `task_definition`
################################################################################

resource "aws_ecs_service" "ignore_task_definition" {
  count = local.create_service && var.ignore_task_definition_changes ? 1 : 0

  region = var.region

  dynamic "alarms" {
    for_each = var.alarms != null ? [var.alarms] : []

    content {
      alarm_names = alarms.value.alarm_names
      enable      = alarms.value.enable
      rollback    = alarms.value.rollback
    }
  }

  availability_zone_rebalancing = var.availability_zone_rebalancing

  dynamic "capacity_provider_strategy" {
    # Set by task set if deployment controller is external
    for_each = !local.is_external_deployment && var.capacity_provider_strategy != null ? var.capacity_provider_strategy : {}

    content {
      base              = capacity_provider_strategy.value.base
      capacity_provider = capacity_provider_strategy.value.capacity_provider
      weight            = coalesce(capacity_provider_strategy.value.weight, 1)
    }
  }

  cluster = var.cluster_arn

  dynamic "deployment_circuit_breaker" {
    for_each = var.deployment_circuit_breaker != null ? [var.deployment_circuit_breaker] : []

    content {
      enable   = deployment_circuit_breaker.value.enable
      rollback = deployment_circuit_breaker.value.rollback
    }
  }

  dynamic "deployment_configuration" {
    for_each = var.deployment_configuration != null ? [var.deployment_configuration] : []

    content {
      strategy             = deployment_configuration.value.strategy
      bake_time_in_minutes = deployment_configuration.value.bake_time_in_minutes

      dynamic "linear_configuration" {
        for_each = deployment_configuration.value.linear_configuration != null ? [deployment_configuration.value.linear_configuration] : []

        content {
          step_bake_time_in_minutes = linear_configuration.value.step_bake_time_in_minutes
          step_percent              = linear_configuration.value.step_percent
        }
      }

      dynamic "canary_configuration" {
        for_each = deployment_configuration.value.canary_configuration != null ? [deployment_configuration.value.canary_configuration] : []

        content {
          canary_bake_time_in_minutes = canary_configuration.value.canary_bake_time_in_minutes
          canary_percent              = canary_configuration.value.canary_percent
        }
      }

      dynamic "lifecycle_hook" {
        for_each = deployment_configuration.value.lifecycle_hook != null ? deployment_configuration.value.lifecycle_hook : {}

        content {
          hook_target_arn  = lifecycle_hook.value.hook_target_arn
          role_arn         = try(coalesce(lifecycle_hook.value.role_arn, local.infrastructure_iam_role_arn))
          lifecycle_stages = lifecycle_hook.value.lifecycle_stages
          hook_details     = lifecycle_hook.value.hook_details
        }
      }
    }
  }

  dynamic "deployment_controller" {
    for_each = var.deployment_controller != null ? [var.deployment_controller] : []

    content {
      type = deployment_controller.value.type
    }
  }

  deployment_maximum_percent         = local.is_daemon || local.is_external_deployment ? null : var.deployment_maximum_percent
  deployment_minimum_healthy_percent = local.is_daemon || local.is_external_deployment ? null : var.deployment_minimum_healthy_percent
  desired_count                      = local.is_daemon || local.is_external_deployment ? null : var.desired_count
  enable_ecs_managed_tags            = var.enable_ecs_managed_tags
  enable_execute_command             = var.enable_execute_command
  force_delete                       = var.force_delete
  force_new_deployment               = local.is_external_deployment ? null : var.force_new_deployment
  health_check_grace_period_seconds  = var.health_check_grace_period_seconds
  iam_role                           = local.iam_role_arn
  launch_type                        = local.is_external_deployment || var.capacity_provider_strategy != null ? null : var.launch_type

  dynamic "load_balancer" {
    # Set by task set if deployment controller is external
    for_each = var.load_balancer != null ? var.load_balancer : {}

    content {
      container_name   = load_balancer.value.container_name
      container_port   = load_balancer.value.container_port
      elb_name         = load_balancer.value.elb_name
      target_group_arn = load_balancer.value.target_group_arn

      dynamic "advanced_configuration" {
        for_each = load_balancer.value.advanced_configuration != null ? [load_balancer.value.advanced_configuration] : []

        content {
          alternate_target_group_arn = advanced_configuration.value.alternate_target_group_arn
          production_listener_rule   = advanced_configuration.value.production_listener_rule
          role_arn                   = try(coalesce(advanced_configuration.value.role_arn, local.infrastructure_iam_role_arn))
          test_listener_rule         = advanced_configuration.value.test_listener_rule
        }
      }
    }
  }

  name = var.name

  dynamic "network_configuration" {
    # Set by task set if deployment controller is external
    for_each = var.network_mode == "awsvpc" && !local.is_external_deployment ? [local.network_configuration] : []

    content {
      assign_public_ip = network_configuration.value.assign_public_ip
      security_groups  = network_configuration.value.security_groups
      subnets          = network_configuration.value.subnets
    }
  }

  dynamic "ordered_placement_strategy" {
    for_each = var.ordered_placement_strategy != null ? var.ordered_placement_strategy : []

    content {
      field = ordered_placement_strategy.value.field
      type  = ordered_placement_strategy.value.type
    }
  }

  dynamic "placement_constraints" {
    for_each = var.placement_constraints != null ? var.placement_constraints : {}

    content {
      expression = placement_constraints.value.expression
      type       = placement_constraints.value.type
    }
  }

  # Set by task set if deployment controller is external
  platform_version    = local.is_fargate && !local.is_external_deployment ? var.platform_version : null
  propagate_tags      = var.propagate_tags
  scheduling_strategy = local.is_fargate ? "REPLICA" : var.scheduling_strategy

  dynamic "service_connect_configuration" {
    for_each = var.service_connect_configuration != null ? [var.service_connect_configuration] : []

    content {
      enabled = service_connect_configuration.value.enabled


      dynamic "access_log_configuration" {
        for_each = service_connect_configuration.value.access_log_configuration != null ? [service_connect_configuration.value.access_log_configuration] : []

        content {
          format                   = access_log_configuration.value.format
          include_query_parameters = access_log_configuration.value.include_query_parameters
        }
      }

      dynamic "log_configuration" {
        for_each = service_connect_configuration.value.log_configuration != null ? [service_connect_configuration.value.log_configuration] : []

        content {
          log_driver = log_configuration.value.log_driver
          options    = log_configuration.value.options

          dynamic "secret_option" {
            for_each = log_configuration.value.secret_option != null ? log_configuration.value.secret_option : []

            content {
              name       = secret_option.value.name
              value_from = secret_option.value.value_from
            }
          }
        }
      }

      namespace = service_connect_configuration.value.namespace

      dynamic "service" {
        for_each = service_connect_configuration.value.service != null ? service_connect_configuration.value.service : []

        content {
          dynamic "client_alias" {
            for_each = service.value.client_alias != null ? [service.value.client_alias] : []

            content {
              dns_name = client_alias.value.dns_name
              port     = client_alias.value.port

              dynamic "test_traffic_rules" {
                for_each = client_alias.value.test_traffic_rules != null ? client_alias.value.test_traffic_rules : []

                content {
                  dynamic "header" {
                    for_each = test_traffic_rules.value.header != null ? [test_traffic_rules.value.header] : []

                    content {
                      name = header.value.name

                      dynamic "value" {
                        for_each = header.value.value != null ? [header.value.value] : []

                        content {
                          exact = value.value.exact
                        }
                      }
                    }
                  }
                }
              }
            }
          }

          discovery_name        = service.value.discovery_name
          ingress_port_override = service.value.ingress_port_override
          port_name             = service.value.port_name

          dynamic "timeout" {
            for_each = service.value.timeout != null ? [service.value.timeout] : []

            content {
              idle_timeout_seconds        = timeout.value.idle_timeout_seconds
              per_request_timeout_seconds = timeout.value.per_request_timeout_seconds
            }
          }

          dynamic "tls" {
            for_each = service.value.tls != null ? [service.value.tls] : []

            content {
              dynamic "issuer_cert_authority" {
                for_each = [tls.value.issuer_cert_authority]

                content {
                  aws_pca_authority_arn = issuer_cert_authority.value.aws_pca_authority_arn
                }
              }

              kms_key  = tls.value.kms_key
              role_arn = tls.value.role_arn
            }
          }
        }
      }
    }
  }

  dynamic "service_registries" {
    # Set by task set if deployment controller is external
    for_each = var.service_registries != null && !local.is_external_deployment ? [var.service_registries] : []

    content {
      container_name = service_registries.value.container_name
      container_port = service_registries.value.container_port
      port           = service_registries.value.port
      registry_arn   = service_registries.value.registry_arn
    }
  }

  sigint_rollback = try(var.deployment_configuration.strategy, null) == "BLUE_GREEN" ? var.sigint_rollback : null

  tags            = merge(var.tags, var.service_tags)
  task_definition = local.task_definition
  triggers        = var.triggers

  dynamic "volume_configuration" {
    for_each = var.volume_configuration != null ? [var.volume_configuration] : []

    content {
      name = try(volume_configuration.value.name, volume_configuration.key)

      dynamic "managed_ebs_volume" {
        for_each = [volume_configuration.value.managed_ebs_volume]

        content {
          encrypted        = managed_ebs_volume.value.encrypted
          file_system_type = managed_ebs_volume.value.file_system_type
          iops             = managed_ebs_volume.value.iops
          kms_key_id       = managed_ebs_volume.value.kms_key_id
          role_arn         = local.infrastructure_iam_role_arn
          size_in_gb       = managed_ebs_volume.value.size_in_gb
          snapshot_id      = managed_ebs_volume.value.snapshot_id

          dynamic "tag_specifications" {
            for_each = managed_ebs_volume.value.tag_specifications != null ? managed_ebs_volume.value.tag_specifications : []

            content {
              resource_type  = tag_specifications.value.resource_type
              propagate_tags = tag_specifications.value.propagate_tags
              tags           = tag_specifications.value.tags
            }
          }

          throughput  = managed_ebs_volume.value.throughput
          volume_type = managed_ebs_volume.value.volume_type
        }
      }
    }
  }

  dynamic "vpc_lattice_configurations" {
    for_each = var.vpc_lattice_configurations != null ? [var.vpc_lattice_configurations] : []

    content {
      role_arn         = local.infrastructure_iam_role_arn
      target_group_arn = vpc_lattice_configurations.value.target_group_arn
      port_name        = vpc_lattice_configurations.value.port_name
    }
  }

  wait_for_steady_state = var.wait_for_steady_state

  dynamic "timeouts" {
    for_each = var.timeouts != null ? [var.timeouts] : []

    content {
      create = timeouts.value.create
      update = timeouts.value.update
      delete = timeouts.value.delete
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.service,
    aws_iam_role_policy_attachment.infrastructure_iam_role_ebs_policy,
    aws_vpc_security_group_ingress_rule.this,
    aws_vpc_security_group_egress_rule.this,
  ]

  lifecycle {
    ignore_changes = [
      desired_count, # Always ignored
      task_definition,
      load_balancer,
    ]
  }
}

################################################################################
# Service - IAM Role
################################################################################

locals {
  # Role is not required if task definition uses `awsvpc` network mode or if a load balancer is not used
  needs_iam_role  = var.network_mode != "awsvpc" && var.load_balancer != null
  create_iam_role = var.create && var.create_iam_role && local.needs_iam_role
  iam_role_arn    = local.needs_iam_role ? try(aws_iam_role.service[0].arn, var.iam_role_arn) : null

  iam_role_name = try(coalesce(var.iam_role_name, var.name), "")
}

data "aws_iam_policy_document" "service_assume" {
  count = local.create_iam_role ? 1 : 0

  statement {
    sid     = "ECSServiceAssumeRole"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "service" {
  count = local.create_iam_role ? 1 : 0

  name        = var.iam_role_use_name_prefix ? null : local.iam_role_name
  name_prefix = var.iam_role_use_name_prefix ? "${local.iam_role_name}-" : null
  path        = var.iam_role_path
  description = try(coalesce(var.iam_role_description, (var.disable_v7_default_name_description ? null : "IAM role for ECS Service ${var.name}")), null)

  assume_role_policy    = data.aws_iam_policy_document.service_assume[0].json
  permissions_boundary  = var.iam_role_permissions_boundary
  force_detach_policies = true

  tags = merge(var.tags, var.iam_role_tags)
}

data "aws_iam_policy_document" "service" {
  count = local.create_iam_role ? 1 : 0

  statement {
    sid       = "ECSService"
    resources = [aws_ecs_cluster.this.arn]

    actions = [
      "ec2:Describe*",
      "elasticloadbalancing:DeregisterInstancesFromLoadBalancer",
      "elasticloadbalancing:DeregisterTargets",
      "elasticloadbalancing:Describe*",
      "elasticloadbalancing:RegisterInstancesWithLoadBalancer",
      "elasticloadbalancing:RegisterTargets"
    ]
  }

  dynamic "statement" {
    for_each = var.iam_role_statements != null ? var.iam_role_statements : []

    content {
      sid           = statement.value.sid
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

resource "aws_iam_policy" "service" {
  count = local.create_iam_role ? 1 : 0

  name        = var.iam_role_use_name_prefix ? null : local.iam_role_name
  name_prefix = var.iam_role_use_name_prefix ? "${local.iam_role_name}-" : null
  description = coalesce(var.iam_role_description, "ECS service policy that allows Amazon ECS to make calls to your load balancer on your behalf")
  policy      = data.aws_iam_policy_document.service[0].json

  tags = merge(var.tags, var.iam_role_tags)
}

resource "aws_iam_role_policy_attachment" "service" {
  count = local.create_iam_role ? 1 : 0

  role       = aws_iam_role.service[0].name
  policy_arn = aws_iam_policy.service[0].arn
}

################################################################################
# Container Definition
################################################################################

module "container_definition" {
  source = "../container-definition"

  region = var.region

  for_each = { for k, v in var.container_definitions : k => v if local.create_task_definition && v.create }

  enable_execute_command  = var.enable_execute_command
  operating_system_family = var.runtime_platform.operating_system_family

  # Container Definition
  command                = each.value.command
  cpu                    = each.value.cpu
  credentialSpecs        = each.value.credentialSpecs
  dependsOn              = each.value.dependsOn
  disableNetworking      = each.value.disableNetworking
  dnsSearchDomains       = each.value.dnsSearchDomains
  dnsServers             = each.value.dnsServers
  dockerLabels           = each.value.dockerLabels
  dockerSecurityOptions  = each.value.dockerSecurityOptions
  entrypoint             = each.value.entrypoint
  environment            = each.value.environment
  environmentFiles       = each.value.environmentFiles
  essential              = each.value.essential
  extraHosts             = each.value.extraHosts
  firelensConfiguration  = each.value.firelensConfiguration
  healthCheck            = each.value.healthCheck
  hostname               = each.value.hostname
  image                  = each.value.image
  interactive            = each.value.interactive
  links                  = each.value.links
  linuxParameters        = each.value.linuxParameters
  logConfiguration       = each.value.logConfiguration
  memory                 = each.value.memory
  memoryReservation      = each.value.memoryReservation
  mountPoints            = each.value.mountPoints
  name                   = coalesce(each.value.name, each.key)
  portMappings           = each.value.portMappings
  privileged             = each.value.privileged
  pseudoTerminal         = each.value.pseudoTerminal
  readonlyRootFilesystem = each.value.readonlyRootFilesystem
  repositoryCredentials  = each.value.repositoryCredentials
  resourceRequirements   = each.value.resourceRequirements
  restartPolicy          = each.value.restartPolicy
  secrets                = each.value.secrets
  startTimeout           = each.value.startTimeout
  stopTimeout            = each.value.stopTimeout
  systemControls         = each.value.systemControls
  ulimits                = each.value.ulimits
  user                   = each.value.user
  versionConsistency     = each.value.versionConsistency
  volumesFrom            = each.value.volumesFrom
  workingDirectory       = each.value.workingDirectory

  # CloudWatch Log Group
  service                                = var.name
  enable_cloudwatch_logging              = each.value.enable_cloudwatch_logging
  create_cloudwatch_log_group            = each.value.create_cloudwatch_log_group
  cloudwatch_log_group_name              = each.value.cloudwatch_log_group_name
  cloudwatch_log_group_use_name_prefix   = each.value.cloudwatch_log_group_use_name_prefix
  cloudwatch_log_group_class             = each.value.cloudwatch_log_group_class
  cloudwatch_log_group_retention_in_days = each.value.cloudwatch_log_group_retention_in_days
  cloudwatch_log_group_kms_key_id        = each.value.cloudwatch_log_group_kms_key_id

  tags = var.tags
}

################################################################################
# Task Definition
################################################################################

locals {
  create_task_definition = var.create && var.create_task_definition
  task_definition        = local.create_task_definition ? aws_ecs_task_definition.this[0].arn : var.task_definition_arn
}

resource "aws_ecs_task_definition" "this" {
  count = local.create_task_definition ? 1 : 0

  region = var.region

  # Convert map of maps to array of maps before JSON encoding
  container_definitions  = jsonencode([for k, v in module.container_definition : v.container_definition])
  cpu                    = var.cpu
  enable_fault_injection = var.enable_fault_injection

  dynamic "ephemeral_storage" {
    for_each = var.ephemeral_storage != null ? [var.ephemeral_storage] : []

    content {
      size_in_gib = ephemeral_storage.value.size_in_gib
    }
  }

  execution_role_arn = try(aws_iam_role.task_exec[0].arn, var.task_exec_iam_role_arn)
  family             = coalesce(var.family, var.name)

  ipc_mode     = var.ipc_mode
  memory       = var.memory
  network_mode = var.network_mode
  pid_mode     = var.pid_mode

  dynamic "placement_constraints" {
    for_each = var.task_definition_placement_constraints != null ? var.task_definition_placement_constraints : {}

    content {
      expression = placement_constraints.value.expression
      type       = placement_constraints.value.type
    }
  }

  dynamic "proxy_configuration" {
    for_each = var.proxy_configuration != null ? [var.proxy_configuration] : []

    content {
      container_name = proxy_configuration.value.container_name
      properties     = proxy_configuration.value.properties
      type           = proxy_configuration.value.type
    }
  }

  requires_compatibilities = var.requires_compatibilities

  dynamic "runtime_platform" {
    for_each = var.runtime_platform != null ? [var.runtime_platform] : []

    content {
      cpu_architecture        = runtime_platform.value.cpu_architecture
      operating_system_family = runtime_platform.value.operating_system_family
    }
  }

  dynamic "volume" {
    for_each = var.volume != null ? var.volume : {}

    content {
      configure_at_launch = volume.value.configure_at_launch

      dynamic "docker_volume_configuration" {
        for_each = volume.value.docker_volume_configuration != null ? [volume.value.docker_volume_configuration] : []

        content {
          autoprovision = docker_volume_configuration.value.autoprovision
          driver        = docker_volume_configuration.value.driver
          driver_opts   = docker_volume_configuration.value.driver_opts
          labels        = docker_volume_configuration.value.labels
          scope         = docker_volume_configuration.value.scope
        }
      }

      dynamic "efs_volume_configuration" {
        for_each = volume.value.efs_volume_configuration != null ? [volume.value.efs_volume_configuration] : []

        content {
          dynamic "authorization_config" {
            for_each = efs_volume_configuration.value.authorization_config != null ? [efs_volume_configuration.value.authorization_config] : []

            content {
              access_point_id = authorization_config.value.access_point_id
              iam             = authorization_config.value.iam
            }
          }

          file_system_id          = efs_volume_configuration.value.file_system_id
          root_directory          = efs_volume_configuration.value.root_directory
          transit_encryption      = efs_volume_configuration.value.transit_encryption
          transit_encryption_port = efs_volume_configuration.value.transit_encryption_port
        }
      }

      dynamic "fsx_windows_file_server_volume_configuration" {
        for_each = volume.value.fsx_windows_file_server_volume_configuration != null ? [volume.value.fsx_windows_file_server_volume_configuration] : []

        content {
          dynamic "authorization_config" {
            for_each = fsx_windows_file_server_volume_configuration.value.authorization_config != null ? [fsx_windows_file_server_volume_configuration.value.authorization_config] : []

            content {
              credentials_parameter = authorization_config.value.credentials_parameter
              domain                = authorization_config.value.domain
            }
          }

          file_system_id = fsx_windows_file_server_volume_configuration.value.file_system_id
          root_directory = fsx_windows_file_server_volume_configuration.value.root_directory
        }
      }

      host_path = volume.value.host_path
      name      = coalesce(volume.value.name, volume.key)
    }
  }

  tags = merge(var.tags, var.task_tags)

  depends_on = [
    aws_iam_role_policy_attachment.tasks,
    aws_iam_role_policy_attachment.task_exec,
    aws_iam_role_policy_attachment.task_exec_additional,
  ]

  lifecycle {
    create_before_destroy = true
  }
}

################################################################################
# Task Execution - IAM Role
# https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task_execution_IAM_role.html
################################################################################

locals {
  task_exec_iam_role_name = coalesce(var.task_exec_iam_role_name, "${var.name}${var.disable_v7_default_name_description ? "" : "-task-exec"}")

  create_task_exec_iam_role = local.create_task_definition && var.create_task_exec_iam_role
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

  name        = var.task_exec_iam_role_use_name_prefix ? null :