data "aws_region" "current" {
  region = var.region

  count = var.create? 1 : 0
}
data "aws_partition" "current" {
  count = var.create? 1 : 0
}
data "aws_caller_identity" "current" {
  count = var.create? 1 : 0
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

resource "aws_ecs_service" "this"aws