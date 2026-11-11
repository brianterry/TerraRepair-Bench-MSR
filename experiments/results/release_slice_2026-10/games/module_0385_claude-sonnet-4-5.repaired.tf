data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

data "aws_region" "current" {}

data "aws_subnet" "runners" {
  id = var.subnet_id
}

data "aws_availability_zone" "runners" {
  name = data.aws_subnet.runners.availability_zone
}

data "aws_ami" "runner_by_filter" {
  count = length(var.runner_ami_id) > 0 ? 0 : 1

  owners      = var.runner_ami_owners
  most_recent = "true"

  dynamic "filter" {
    for_each = var.runner_ami_filter

    content {
      name   = filter.key
      values = filter.value
    }
  }
}

data "aws_ami" "docker_machine_by_filter" {
  count = var.runner_worker.type == "docker+machine" && length(var.runner_worker_docker_machine_ami_id) == 0 ? 1 : 0

  owners      = var.runner_worker_docker_machine_ami_owners
  most_recent = "true"

  dynamic "filter" {
    for_each = var.runner_worker_docker_machine_ami_filter

    content {
      name   = filter.key
      values = filter.value
    }
  }
}

data "aws_ami" "docker_autoscaler_by_filter" {
  count = var.runner_worker.type == "docker-autoscaler" && length(var.runner_worker_docker_autoscaler_ami_id) == 0 ? 1 : 0

  owners      = var.runner_worker_docker_autoscaler_ami_owners
  most_recent = "true"

  dynamic "filter" {
    for_each = var.runner_worker_docker_autoscaler_ami_filter

    content {
      name   = filter.key
      values = filter.value
    }
  }
}

resource "aws_launch_template" "this" {
  count = var.runner_worker.type == "docker-autoscaler" ? 1 : 0

  name          = "${local.name_runner_agent_instance}-worker-launch-template"
  user_data     = var.runner_worker_docker_autoscaler_instance.start_script_compression_algorithm == "gzip" ? base64gzip(var.runner_worker_docker_autoscaler_instance.start_script) : base64encode(var.runner_worker_docker_autoscaler_instance.start_script)
  image_id      = length(var.runner_worker_docker_autoscaler_ami_id) > 0 ? var.runner_worker_docker_autoscaler_ami_id : data.aws_ami.docker_autoscaler_by_filter[0].id
  instance_type = length(var.runner_worker_docker_autoscaler_asg.types) > 0 ? var.runner_worker_docker_autoscaler_asg.types[0] : var.runner_worker_docker_autoscaler_asg.default_instance_type
  key_name      = aws_key_pair.autoscaler[0].key_name
  ebs_optimized = var.runner_worker_docker_autoscaler_instance.ebs_optimized

  monitoring {
    enabled = var.runner_worker_docker_autoscaler_instance.monitoring
  }

  iam_instance_profile {
    name = aws_iam_instance_profile.docker_autoscaler[0].name
  }

  network_interfaces {
    security_groups             = [aws_security_group.docker_autoscaler[0].id]
    associate_public_ip_address = !var.runner_worker_docker_autoscaler_instance.private_address_only
  }

  block_device_mappings {
    device_name = var.runner_worker_docker_autoscaler_instance.root_device_name

    ebs {
      volume_size = var.runner_worker_docker_autoscaler_instance.root_size
      volume_type = var.runner_worker_docker_autoscaler_instance.volume_type
      iops        = contains(["gp3", "io1", "io2"], var.runner_worker_docker_autoscaler_instance.volume_type) ? var.runner_worker_docker_autoscaler_instance.volume_iops : null
      throughput  = var.runner_worker_docker_autoscaler_instance.volume_type == "gp3" ? var.runner_worker_docker_autoscaler_instance.volume_throughput : null
      encrypted   = true
      kms_key_id  = local.kms_key_arn != "" ? local.kms_key_arn : null
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags          = local.tags
  }
  tag_specifications {
    resource_type = "volume"
    tags          = local.tags
  }
  tag_specifications {
    resource_type = "network-interface"
    tags          = local.tags
  }

  tags = local.tags

  metadata_options {
    http_tokens                 = var.runner_worker_docker_autoscaler_instance.http_tokens
    http_put_response_hop_limit = var.runner_worker_docker_autoscaler_instance.http_put_response_hop_limit
    instance_metadata_tags      = "enabled"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "autoscaler" {
  count = var.runner_worker.type == "docker-autoscaler" ? 1 : 0

  name                  = "${local.name_runner_agent_instance}-asg"
  capacity_rebalance    = false
  protect_from_scale_in = true
  suspended_processes   = ["AZRebalance"]

  dynamic "launch_template" {
    for_each = var.runner_worker_docker_autoscaler_asg.enable_mixed_instances_policy ? [] : [1]
    content {
      id      = aws_launch_template.this[0].id
      version = aws_launch_template.this[0].latest_version
    }
  }

  dynamic "mixed_instances_policy" {
    for_each = var.runner_worker_docker_autoscaler_asg.enable_mixed_instances_policy ? [1] : []

    content {
      instances_distribution {
        on_demand_base_capacity                  = var.runner_worker_docker_autoscaler_asg.on_demand_base_capacity
        on_demand_percentage_above_base_capacity = var.runner_worker_docker_autoscaler_asg.on_demand_percentage_above_base_capacity
        spot_allocation_strategy                 = var.runner_worker_docker_autoscaler_asg.spot_allocation_strategy
        spot_instance_pools                      = var.runner_worker_docker_autoscaler_asg.spot_instance_pools
      }
      launch_template {
        launch_template_specification {
          launch_template_id = aws_launch_template.this[0].id
          version            = aws_launch_template.this[0].latest_version
        }

        dynamic "override" {
          for_each = var.runner_worker_docker_autoscaler_asg.types
          content {
            instance_type = override.value
          }
        }

        dynamic "override" {
          for_each = var.runner_worker_docker_autoscaler_asg.instance_requirements
          content {
            instance_requirements {
              allowed_instance_types = override.value.allowed_instance_types
              cpu_manufacturers      = override.value.cpu_manufacturers
              instance_generations   = override.value.instance_generations
              burstable_performance  = override.value.burstable_performance
              dynamic "memory_mib" {
                for_each = [override.value.memory_mib]
                content {
                  max = memory_mib.value.max
                  min = memory_mib.value.min
                }
              }
              dynamic "vcpu_count" {
                for_each = [override.value.vcpu_count]
                content {
                  max = vcpu_count.value.max
                  min = vcpu_count.value.min
                }
              }
            }
          }
        }
      }
    }
  }

  dynamic "instance_refresh" {
    for_each = var.runner_worker_docker_autoscaler_asg.upgrade_strategy == "rolling" ? [1] : []
    content {
      strategy = "Rolling"
      preferences {
        min_healthy_percentage = var.runner_worker_docker_autoscaler_asg.instance_refresh_min_healthy_percentage
      }
      triggers = var.runner_worker_docker_autoscaler_asg.instance_refresh_triggers
    }
  }

  vpc_zone_identifier       = var.runner_worker_docker_autoscaler_asg.subnet_ids
  max_size                  = var.runner_worker.max_jobs
  min_size                  = 0
  desired_capacity          = 0
  health_check_grace_period = var.runner_worker_docker_autoscaler_asg.health_check_grace_period
  health_check_type         = var.runner_worker_docker_autoscaler_asg.health_check_type
  force_delete              = true
  enabled_metrics           = var.runner_worker_docker_autoscaler_asg.enabled_metrics

  dynamic "tag" {
    for_each = local.tags
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }

  lifecycle {
    ignore_changes = [
      desired_capacity
    ]
  }
}

resource "aws_iam_instance_profile" "docker_autoscaler" {
  count = var.runner_worker.type == "docker-autoscaler" ? 1 : 0
  name  = "${local.name_iam_objects}-docker-autoscaler"
  role  = aws_iam_role.docker_autoscaler[0].name
  tags  = local.tags
}

resource "tls_private_key" "autoscaler" {
  count = var.runner_worker.type == "docker-autoscaler" ? 1 : 0

  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "autoscaler" {
  count = var.runner_worker.type == "docker-autoscaler" ? 1 : 0

  key_name   = "${var.environment}-${var.runner_worker_docker_autoscaler.key_pair_name}"
  public_key = tls_private_key.autoscaler[0].public_key_openssh

  tags = local.tags
}

resource "aws_iam_role" "docker_autoscaler" {
  count                = var.runner_worker.type == "docker-autoscaler" ? 1 : 0
  name                 = "${local.name_iam_objects}-docker-autoscaler"
  assume_role_policy   = length(var.runner_worker_docker_autoscaler_role.assume_role_policy_json) > 0 ? var.runner_worker_docker_autoscaler_role.assume_role_policy_json : templatefile("${path.module}/policies/instance-role-trust-policy.json", {})
  permissions_boundary = var.iam_permissions_boundary == "" ? null : "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:policy/${var.iam_permissions_boundary}"

  tags = merge(local.tags, var.runner_worker_docker_autoscaler_role.additional_tags)
}

resource "aws_iam_policy" "instance_docker_autoscaler_policy" {
  count = var.runner_worker.type == "docker-autoscaler" && var.runner_role.create_role_profile ? 1 : 0

  name        = "${local.name_iam_objects}-docker-autoscaler"
  path        = "/"
  description = "Policy for docker autoscaler."
  policy = templatefile("${path.module}/policies/instance-docker-autoscaler-policy.json",
    {
      aws_region          = data.aws_region.current.region
      partition           = data.aws_partition.current.partition
      autoscaler_asg_arn  = aws_autoscaling_group.autoscaler[0].arn
      autoscaler_asg_name = aws_autoscaling_group.autoscaler[0].name
  })

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "instance_docker_autoscaler_policy" {
  count = var.runner_worker.type == "docker-autoscaler" && var.runner_role.create_role_profile ? 1 : 0

  role       = aws_iam_role.instance[0].name
  policy_arn = aws_iam_policy.instance_docker_autoscaler_policy[0].arn
}

resource "aws_iam_role_policy_attachment" "docker_autoscaler_user_defined_policies" {
  count = var.runner_worker.type == "docker-autoscaler" ? length(var.runner_worker_docker_autoscaler_role.policy_arns) : 0

  role       = aws_iam_role.docker_autoscaler[0].name
  policy_arn = var.runner_worker_docker_autoscaler_role.policy_arns[count.index]
}

resource "aws_iam_role_policy_attachment" "docker_autoscaler_session_manager_aws_managed" {
  count = (var.runner_worker.type == "docker-autoscaler" && var.runner_worker.ssm_access) ? 1 : 0

  role       = aws_iam_role.docker_autoscaler[0].name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_security_group" "docker_autoscaler" {
  count       = var.runner_worker.type == "docker-autoscaler" ? 1 : 0
  name_prefix = "${local.name_sg}-docker-autoscaler"
  vpc_id      = var.vpc_id
  description = "Docker-autoscaler security group"

  tags = merge(
    local.tags,
    {
      "Name" = format("%s", local.name_sg)
    },
  )
}

resource "aws_vpc_security_group_ingress_rule" "docker_autoscaler_ingress" {
  for_each = var.runner_worker.type == "docker-autoscaler" ? var.runner_worker_ingress_rules : {}

  security_group_id = aws_security_group.docker_autoscaler[0].id

  from_port   = each.value.from_port
  to_port     = each.value.to_port
  ip_protocol = each.value.protocol

  description                  = each.value.description
  prefix_list_id               = each.value.prefix_list_id
  referenced_security_group_id = each.value.security_group
  cidr_ipv4                    = each.value.cidr_block
  cidr_ipv6                    = each.value.ipv6_cidr_block

  tags = local.tags
}

resource "aws_vpc_security_group_ingress_rule" "docker_autoscaler_internal_traffic" {
  count = var.runner_worker.type == "docker-autoscaler" ? 1 : 0

  security_group_id            = aws_security_group.docker_autoscaler[0].id
  from_port                    = -1
  to_port                      = -1
  ip_protocol                  = "-1"
  description                  = "Allow ALL Ingress traffic between Runner Manager and Docker-autoscaler workers security group"
  referenced_security_group_id = aws_security_group.runner.id

  tags = local.tags
}

resource "aws_vpc_security_group_egress_rule" "docker_autoscaler_egress" {
  for_each = var.runner_worker.type == "docker-autoscaler" ? var.runner_worker_egress_rules : {}

  security_group_id = aws_security_group.docker_autoscaler[0].id

  from_port   = each.value.from_port
  to_port     = each.value.to_port
  ip_protocol = each.value.protocol

  description                  = each.value.description
  prefix_list_id               = each.value.prefix_list_id
  referenced_security_group_id = each.value.security_group
  cidr_ipv4                    = each.value.cidr_block
  cidr_ipv6                    = each.value.ipv6_cidr_block

  tags = local.tags
}

locals {
  template_runner_docker_machine = templatefile("${path.module}/template/runner-docker-machine-config.tftpl",
    {
      runners_idle_count     = var.runner_worker_docker_machine_instance.idle_count
      runners_idle_time      = var.runner_worker_docker_machine_instance.idle_time
      runners_max_builds     = local.runners_max_builds_string
      docker_machine_name    = format("%s-%s", local.runner_tags_merged["Name"], "%s")
      runners_instance_types = var.runner_worker_docker_machine_instance.types
      aws_region             = data.aws_region.current.region
      runners_aws_zone       = data.aws_availability_zone.runners.name_suffix
      runners_userdata       = var.runner_worker_docker_machine_instance.start_script

      runners_vpc_id           = var.vpc_id
      runners_subnet_id        = var.subnet_id
      runners_subnet_ids       = length(var.runner_worker_docker_machine_instance.subnet_ids) > 0 ? var.runner_worker_docker_machine_instance.subnet_ids : [var.subnet_id]
      runners_instance_profile = var.runner_worker.type == "docker+machine" ? aws_iam_instance_profile.docker_machine[0].name : ""

      runners_use_private_address_only = var.runner_worker_docker_machine_instance.private_address_only
      runners_use_private_address      = !var.runner_worker_docker_machine_instance.private_address_only
      runners_request_spot_instance    = var.runner_worker_docker_machine_instance_spot.enable
      runners_spot_price_bid           = var.runner_worker_docker_machine_instance_spot.max_price == "on-demand-price" || var.runner_worker_docker_machine_instance_spot.max_price == null ? "" : var.runner_worker_docker_machine_instance_spot.max_price
      runners_security_group_name      = var.runner_worker.type == "docker+machine" ? aws_security_group.docker_machine[0].name : ""

      runners_tags                      = replace(replace(local.runner_tags_string, ",,", ","), "/,$/", "")
      runners_ebs_optimized             = var.runner_worker_docker_machine_instance.ebs_optimized
      runners_monitoring                = var.runner_worker_docker_machine_instance.monitoring
      runners_iam_instance_profile_name = var.runner_worker_docker_machine_role.profile_name
      runners_root_size                 = var.runner_worker_docker_machine_instance.root_size
      runners_volume_type               = var.runner_worker_docker_machine_instance.volume_type
      runners_ami                       = var.runner_worker.type == "docker+machine" ? (length(var.runner_worker_docker_machine_ami_id) > 0 ? var.runner_worker_docker_machine_ami_id : data.aws_ami.docker_machine_by_filter[0].id) : ""
      use_fleet                         = var.runner_worker_docker_machine_fleet.enable
      launch_template                   = var.runner_worker_docker_machine_fleet.enable == true ? aws_launch_template.fleet_gitlab_runner[0].name : ""
      docker_machine_options            = length(local.docker_machine_options_string) == 1 ? "" : local.docker_machine_options_string
      runners_max_growth_rate           = var.runner_worker_docker_machine_instance.max_growth_rate
      runners_volume_kms_key            = local.kms_key_arn
  })
}

resource "aws_iam_instance_profile" "docker_machine" {
  count = var.runner_worker.type == "docker+machine" ? 1 : 0
  name  = "${local.name_iam_objects}-docker-machine"
  role  = aws_iam_role.docker_machine[0].name
  tags  = local.tags
}

resource "aws_key_pair" "fleet" {
  count = var.runner_worker_docker_machine_fleet.enable == true && var.runner_worker.type == "docker+machine" ? 1 : 0

  key_name   = "${var.environment}-${var.runner_worker_docker_machine_fleet.key_pair_name}"
  public_key = tls_private_key.fleet[0].public_key_openssh

  tags = local.tags
}

resource "tls_private_key" "fleet" {
  count = var.runner_worker_docker_machine_fleet.enable == true && var.runner_worker.type == "docker+machine" ? 1 : 0

  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_launch_template" "fleet_gitlab_runner" {
  count       = var.runner_worker_docker_machine_fleet.enable == true && var.runner_worker.type == "docker+machine" ? 1 : 0
  name_prefix = "${local.name_runner_agent_instance}-worker-"

  key_name               = aws_key_pair.fleet[0].key_name
  image_id               = length(var.runner_worker_docker_machine_ami_id) > 0 ? var.runner_worker_docker_machine_ami_id : data.aws_ami.docker_machine_by_filter[0].id
  user_data              = base64gzip(var.runner_worker_docker_machine_instance.start_script)
  instance_type          = var.runner_worker_docker_machine_instance.types[0]
  update_default_version = true
  ebs_optimized          = var.runner_worker_docker_machine_instance.ebs_optimized
  monitoring {
    enabled = var.runner_worker_docker_machine_instance.monitoring
  }
  block_device_mappings {
    device_name = var.runner_worker_docker_machine_instance.root_device_name

    ebs {
      volume_size = var.runner_worker_docker_machine_instance.root_size
      volume_type = var.runner_worker_docker_machine_instance.volume_type
      iops        = contains(["gp3", "io1", "io2"], var.runner_worker_docker_machine_instance.volume_type) ? var.runner_worker_docker_machine_instance.volume_iops : null
      throughput  = var.runner_worker_docker_machine_instance.volume_type == "gp3" ? var.runner_worker_docker_machine_instance.volume_throughput : null
      encrypted   = true
      kms_key_id  = local.kms_key_arn != "" ? local.kms_key_arn : null
    }
  }

  iam_instance_profile {
    name = aws_iam_instance_profile.docker_machine[0].name
  }

  network_interfaces {
    security_groups             = [aws_security_group.docker_machine[0].id]
    associate_public_ip_address = !var.runner_worker_docker_machine_instance.private_address_only
  }

  tag_specifications {
    resource_type = "instance"
    tags          = local.tags
  }
  tag_specifications {
    resource_type = "volume"
    tags          = local.tags
  }
  tag_specifications {
    resource_type = "network-interface"
    tags          = local.tags
  }

  tags = local.tags

  metadata_options {
    http_tokens                 = var.runner_worker_docker_machine_ec2_metadata_options.http_tokens
    http_put_response_hop_limit = var.runner_worker_docker_machine_ec2_metadata_options.http_put_response_hop_limit
    instance_metadata_tags      = "enabled"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_iam_role" "docker_machine" {
  count                = var.runner_worker.type == "docker+machine" ? 1 : 0
  name                 = "${local.name_iam_objects}-docker-machine"
  assume_role_policy   = length(var.runner_worker_docker_machine_role.assume_role_policy_json) > 0 ? var.runner_worker_docker_machine_role.assume_role_policy_json : templatefile("${path.module}/policies/instance-role-trust-policy.json", {})
  permissions_boundary = var.iam_permissions_boundary == "" ? null : "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:policy/${var.iam_permissions_boundary}"

  tags = merge(local.tags, var.runner_worker_docker_machine_role.additional_tags)
}

resource "aws_iam_policy" "instance_docker_machine_policy" {
  count = var.runner_worker.type == "docker+machine" && var.runner_role.create_role_profile ? 1 : 0

  name        = "${local.name_iam_objects}-docker-machine"
  path        = "/"
  description = "Policy for docker machine."
  policy = templatefile("${path.module}/policies/instance-docker-machine-policy.json",
    {
      docker_machine_role_arn = aws_iam_role.docker_machine[0].arn
  })

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "instance_docker_machine_policy" {
  count = var.runner_worker.type == "docker+machine" && var.runner_role.create_role_profile ? 1 : 0

  role       = aws_iam_role.instance[0].name
  policy_arn = aws_iam_policy.instance_docker_machine_policy[0].arn
}

resource "aws_iam_role_policy_attachment" "docker_machine_user_defined_policies" {
  count = var.runner_worker.type == "docker+machine" ? length(var.runner_worker_docker_machine_role.policy_arns) : 0

  role       = aws_iam_role.docker_machine[0].name
  policy_arn = var.runner_worker_docker_machine_role.policy_arns[count.index]
}

resource "aws_iam_role_policy_attachment" "docker_machine_session_manager_aws_managed" {
  count = (var.runner_worker.type == "docker+machine" && var.runner_worker.ssm_access) ? 1 : 0

  role       = aws_iam_role.docker_machine[0].name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

locals {
  security_groups_ping = var.runner_networking.allow_incoming_ping && length(var.runner_networking.allow_incoming_ping_security_group_ids) > 0 ? concat(var.runner_networking.allow_incoming_ping_security_group_ids, [aws_security_group.runner.id]) : []
}

resource "aws_security_group" "docker_machine" {
  count = var.runner_worker.type == "docker+machine" ? 1 : 0

  name_prefix = "${local.name_sg}-docker-machine"
  vpc_id      = var.vpc_id
  description = var.runner_worker_docker_machine_security_group_description

  tags = merge(
    local.tags,
    {
      "Name" = format("%s", local.name_sg)
    },
  )
}

resource "aws_vpc_security_group_ingress_rule" "docker_machine" {
  for_each = var.runner_worker.type == "docker+machine" ? var.runner_worker_ingress_rules : {}

  security_group_id = aws_security_group.docker_machine[0].id

  from_port   = each.value.from_port
  to_port     = each.value.to_port
  ip_protocol = each.value.protocol

  description                  = each.value.description
  prefix_list_id               = each.value.prefix_list_id
  referenced_security_group_id = each.value.security_group
  cidr_ipv4                    = each.value.cidr_block
  cidr_ipv6                    = each.value.ipv6_cidr_block

  tags = local.tags
}

resource "aws_vpc_security_group_egress_rule" "docker_machine" {
  for_each = var.runner_worker.type == "docker+machine" ? var.runner_worker_egress_rules : {}

  security_group_id = aws_security_group.docker_machine[0].id

  from_port   = each.value.from_port
  to_port     = each.value.to_port
  ip_protocol = each.value.protocol

  description                  = each.value.description
  prefix_list_id               = each.value.prefix_list_id
  referenced_security_group_id = each.value.security_group
  cidr_ipv4                    = each.value.cidr_block
  cidr_ipv6                    = each.value.ipv6_cidr_block

  tags = local.tags
}

resource "aws_vpc_security_group_ingress_rule" "docker_machine_docker_runner" {
  count = var.runner_worker.type == "docker+machine" ? 1 : 0

  security_group_id = aws_security_group.docker_machine[0].id

  from_port   = 2376
  to_port     = 2376
  ip_protocol = "tcp"

  referenced_security_group_id = aws_security_group.runner.id

  description = format(
    "Allow docker-machine traffic from group %s to docker-machine instances in group %s",
    aws_security_group.runner.name,
    aws_security_group.docker_machine[0].name
  )

  tags = local.tags
}

resource "aws_vpc_security_group_ingress_rule" "docker_machine_ssh_runner" {
  count = var.runner_worker.type == "docker+machine" ? 1 : 0

  security_group_id = aws_security_group.docker_machine[0].id

  from_port   = 22
  to_port     = 22
  ip_protocol = "tcp"

  referenced_security_group_id = aws_security_group.runner.id

  description = format(
    "Allow SSH traffic from %s to docker-machine instances in group %s on port 22",
    aws_security_group.runner.id,
    aws_security_group.docker_machine[0].name
  )

  tags = local.tags
}

resource "aws_vpc_security_group_ingress_rule" "docker_machine_ping_runner" {
  count = var.runner_worker.type == "docker+machine" ? length(local.security_groups_ping) : 0

  security_group_id = aws_security_group.docker_machine[0].id

  from_port   = -1
  to_port     = -1
  ip_protocol = "icmp"

  referenced_security_group_id = element(local.security_groups_ping, count.index)

  description = format(
    "Allow ICMP traffic from %s to docker-machine instances in group %s",
    element(local.security_groups_ping, count.index),
    aws_security_group.docker_machine[0].name
  )

  tags = local.tags
}

resource "aws_vpc_security_group_ingress_rule" "docker_machine_docker_self" {
  count = var.runner_worker.type == "docker+machine" ? 1 : 0

  security_group_id = aws_security_group.docker_machine[0].id

  from_port   = 2376
  to_port     = 2376
  ip_protocol = "tcp"

  referenced_security_group_id = aws_security_group.docker_machine[0].id

  description = format(
    "Allow docker-machine traffic within group %s on port 2376",
    aws_security_group.docker_machine[0].name,
  )

  tags = local.tags
}

resource "aws_vpc_security_group_ingress_rule" "docker_machine_ssh_self" {
  count = var.runner_worker.type == "docker+machine" ? 1 : 0

  security_group_id = aws_security_group.docker_machine[0].id

  from_port                    = 22
  to_port                      = 22
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.docker_machine[0].id

  description = format(
    "Allow SSH traffic within group %s on port 22",
    aws_security_group.docker_machine[0].name,
  )

  tags = local.tags
}

resource "aws_vpc_security_group_ingress_rule" "docker_machine_ping_self" {
  count = (var.runner_worker.type == "docker+machine" && var.runner_networking.allow_incoming_ping) ? 1 : 0

  security_group_id = aws_security_group.docker_machine[0].id

  from_port                    = -1
  to_port                      = -1
  ip_protocol                  = "icmp"
  referenced_security_group_id = aws_security_group.docker_machine[0].id

  description = format(
    "Allow ICMP traffic within group %s",
    aws_security_group.docker_machine[0].name,
  )

  tags = local.tags
}

resource "aws_kms_key" "default" {
  count = var.enable_managed_kms_key ? 1 : 0

  description             = "GitLab Runner module managed key - ${var.environment}"
  deletion_window_in_days = var.kms_managed_deletion_rotation_window_in_days > 0 ? var.kms_managed_deletion_rotation_window_in_days : null
  enable_key_rotation     = var.kms_managed_deletion_rotation_window_in_days > 0 ? true : false
  tags                    = local.tags
  policy = templatefile("${path.module}/policies/kms-policy.json",
    {
      partition  = data.aws_partition.current.partition
      aws_region = data.aws_region.current.region
      account_id = data.aws_caller_identity.current.account_id
    }
  )
}

resource "aws_kms_alias" "default" {
  count         = var.enable_managed_kms_key && var.kms_managed_alias_name != "" ? 1 : 0
  name          = "alias/${var.kms_managed_alias_name}"
  target_key_id = aws_kms_key.default[0].key_id
}

locals {
  pre_install_gitlab_certificate = (
    length(var.runner_gitlab.certificate) > 0
    ? <<-EOT
      mkdir -p /etc/gitlab-runner/certs/
      cat <<- EOF > /etc/gitlab-runner/certs/gitlab.crt
      ${var.runner_gitlab.certificate}
      EOF
    EOT
    : ""
  )
  pre_install_ca_certificate = (
    length(var.runner_gitlab.ca_certificate) > 0
    ? <<-EOT
      mkdir -p /etc/gitlab-runner/certs/
      cat <<- EOF > /etc/gitlab-runner/certs/ca.crt
      ${var.runner_gitlab.ca_certificate}
      EOF
    EOT
    : ""
  )
  pre_install_certificates_end = <<-EOT
    chmod 600 /etc/gitlab-runner/certs/*.crt
    chmod -R a+r /etc/gitlab-runner
    cp /etc/gitlab-runner/certs/*.crt /etc/pki/ca-trust/source/anchors
    update-ca-trust extract
  EOT
  pre_install_certificates = (
    length(var.runner_gitlab.certificate) + length(var.runner_gitlab.ca_certificate) > 0
    ? join("\n", [
      local.pre_install_gitlab_certificate,
      local.pre_install_ca_certificate,
      local.pre_install_certificates_end
    ])
    : ""
  )

  aws_iam_role_instance_name = coalesce(
    var.runner_role.role_profile_name,
    "${local.name_iam_objects}-instance"
  )
  aws_iam_role_instance_arn = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/${local.aws_iam_role_instance_name}"

  docker_machine_options_string = format(
    ",\"amazonec2-metadata-token=${var.runner_worker_docker_machine_ec2_metadata_options.http_tokens}\", \"amazonec2-metadata-token-response-hop-limit=${var.runner_worker_docker_machine_ec2_metadata_options.http_put_response_hop_limit}\",%s",
    join(",", formatlist("%q", concat(var.runner_worker_docker_machine_ec2_options, local.runners_docker_registry_mirror_option))),
  )

  runners_docker_registry_mirror_option = var.runner_worker_docker_machine_instance.docker_registry_mirror_url == "" ? [] : ["engine-registry-mirror=${var.runner_worker_docker_machine_instance.docker_registry_mirror_url}"]

  runners_docker_options_toml = templatefile("${path.module}/template/runners_docker_options.tftpl", {
    options = merge({
      for key, value in var.runner_worker_docker_options : key => value if value != null && key != "volumes" && key != "pull_policies"
      }, {
      pull_policy = var.runner_worker_docker_options.pull_policies
      volumes     = local.runners_volumes
    })
    }
  )

  runners_max_builds_string = var.runner_worker_docker_machine_instance.destroy_after_max_builds == 0 ? "" : format("MaxBuilds = %d", var.runner_worker_docker_machine_instance.destroy_after_max_builds)

  secure_parameter_store_runner_token_key  = "${var.environment}-${var.runner_gitlab_token_secure_parameter_store}"
  secure_parameter_store_runner_sentry_dsn = "${var.environment}-${var.runner_sentry_secure_parameter_store_name}"

  name_runner_agent_instance = var.runner_instance.name_prefix == null ? local.tags["Name"] : var.runner_instance.name_prefix
  name_sg                    = var.security_group_prefix == "" ? local.tags["Name"] : var.security_group_prefix
  name_iam_objects           = var.iam_object_prefix == "" ? local.tags["Name"] : var.iam_object_prefix

  runners_volumes = concat(var.runner_worker_docker_options.volumes, var.runner_worker_docker_add_dind_volumes ? ["/certs/client", "/builds", "/var/run/docker.sock:/var/run/docker.sock"] : [])

  runners_docker_services = templatefile("${path.module}/template/runners_docker_services.tftpl", {
    runners_docker_services = var.runner_worker_docker_services
    }
  )

  docker_machine_version_used          = split(".", split("-", var.runner_install.docker_machine_version)[0])
  docker_machine_version_with_name_tag = split(".", "0.16.2")
  docker_machine_version_test = [
    for i, j in reverse(range(length(local.docker_machine_version_used)))
    : signum(local.docker_machine_version_with_name_tag[i] - local.docker_machine_version_used[i]) * pow(10, j)
  ]

  docker_machine_adds_name_tag = signum(sum(local.docker_machine_version_test)) <= 0

  runner_worker_graceful_terminate_heartbeat_timeout = (var.runner_terminate_ec2_lifecycle_timeout_duration == null
    ? min(7200, tonumber(coalesce(var.runner_gitlab_registration_config.maximum_timeout, 0)) + 300)
  : var.runner_terminate_ec2_lifecycle_timeout_duration)

  kms_key_arn = local.provided_kms_key == "" && var.enable_managed_kms_key ? aws_kms_key.default[0].arn : local.provided_kms_key
}

resource "local_file" "config_toml" {
  count = var.debug.write_runner_config_to_file ? 1 : 0

  content  = local.template_runner_config
  filename = "${path.root}/debug/${local.name_runner_agent_instance}/runner_config.toml"
}

resource "local_file" "user_data" {
  count = var.debug.write_runner_user_data_to_file ? 1 : 0

  content  = local.template_user_data
  filename = "${path.root}/debug/${local.name_runner_agent_instance}/user_data.sh"
}

resource "aws_iam_role_policy" "instance" {
  count  = var.runner_cloudwatch.enable && var.runner_role.create_role_profile ? 1 : 0
  name   = "${local.name_iam_objects}-logging"
  role   = var.runner_role.create_role_profile ? aws_iam_role.instance[0].name : local.aws_iam_role_instance_name
  policy = templatefile("${path.module}/policies/instance-logging-policy.json", { partition = data.aws_partition.current.partition })
}

locals {
  logging_user_data = templatefile("${path.module}/template/logging.tftpl",
    {
      log_group_name = var.runner_cloudwatch.log_group_name != null ? var.runner_cloudwatch.log_group_name : var.environment
  })
  provided_kms_key = var.kms_key_id != "" ? var.kms_key_id : ""
}

resource "aws_cloudwatch_log_group" "environment" {
  count             = var.runner_cloudwatch.enable ? 1 : 0
  name              = var.runner_cloudwatch.log_group_name != null ? var.runner_cloudwatch.log_group_name : var.environment
  retention_in_days = var.runner_cloudwatch.retention_days
  tags              = local.tags

  kms_key_id = local.kms_key_arn
}

resource "aws_ssm_parameter" "runner_registration_token" {
  name  = local.secure_parameter_store_runner_token_key
  type  = "SecureString"
  value = "null"

  key_id = local.kms_key_arn

  tags = local.tags

  lifecycle {
    ignore_changes = [value]
  }
}

resource "aws_ssm_parameter" "runner_sentry_dsn" {
  name  = local.secure_parameter_store_runner_sentry_dsn
  type  = "SecureString"
  value = "null"

  key_id = local.kms_key_arn

  tags = local.tags

  lifecycle {
    ignore_changes = [value]
  }
}

locals {
  template_user_data = templatefile("${path.module}/template/user-data.tftpl",
    {
      eip                 = var.runner_instance.use_eip ? local.template_eip : ""
      logging             = var.runner_cloudwatch.enable ? local.logging_user_data : ""
      gitlab_runner       = local.template_gitlab_runner
      user_data_trace_log = var.debug.trace_runner_user_data
      yum_update          = var.runner_install.yum_update ? local.file_yum_update : ""
      extra_config        = var.runner_install.start_script
  })

  runner_version_split = split(".", var.runner_gitlab.runner_version)
  runner_version_major = parseint(local.runner_version_split[0], 10)
  runner_version_minor = parseint(local.runner_version_split[1], 10)
  runner_use_new_fleeting_install = (local.runner_version_major == 16 && local.runner_version_minor >= 11) || local.runner_version_major > 16

  file_yum_update = file("${path.module}/template/yum_update.tftpl")

  template_eip = templatefile("${path.module}/template/eip.tftpl", {
    eip = join(",", [for eip in aws_eip.gitlab_runner : eip.public_ip])
  })

  template_gitlab_runner = templatefile("${path.module}/template/gitlab-runner.tftpl",
    {
      aws_region                                                   = data.aws_region.current.region
      gitlab_runner_version                                        = var.runner_gitlab.runner_version
      docker_machine_version                                       = var.runner_install.docker_machine_version
      docker_machine_download_url                                  = var.runner_install.docker_machine_download_url
      runners_config                                               = local.template_runner_config
      runners_userdata                                             = var.runner_worker_docker_machine_instance.start_script
      runners_executor                                             = var.runner_worker.type
      runners_install_amazon_ecr_credential_helper                 = var.runner_install.amazon_ecr_credential_helper
      curl_cacert                                                  = length(var.runner_gitlab.certificate) > 0 ? "--cacert /etc/gitlab-runner/certs/gitlab.crt" : ""
      pre_install_certificates                                     = local.pre_install_certificates
      pre_install                                                  = var.runner_install.pre_install_script
      post_install                                                 = var.runner_install.post_install_script
      runners_gitlab_url                                           = var.runner_gitlab.url
      runners_token                                                = var.runner_gitlab.registration_token
      preregistered_runner_token_ssm_parameter_name                = var.runner_gitlab.preregistered_runner_token_ssm_parameter_name
      secure_parameter_store_gitlab_runner_registration_token_name = var.runner_gitlab_registration_token_secure_parameter_store_name
      secure_parameter_store_runner_token_key                      = local.secure_parameter_store_runner_token_key
      secure_parameter_store_runner_sentry_dsn                     = local.secure_parameter_store_runner_sentry_dsn
      secure_parameter_store_gitlab_token_name                     = var.runner_gitlab.access_token_secure_parameter_store_name
      secure_parameter_store_region                                = data.aws_region.current.region
      gitlab_runner_registration_token                             = var.runner_gitlab_registration_config.registration_token
      gitlab_runner_description                                    = var.runner_gitlab_registration_config["description"]
      gitlab_runner_tag_list                                       = var.runner_gitlab_registration_config["tag_list"]
      gitlab_runner_locked_to_project                              = var.runner_gitlab_registration_config["locked_to_project"]
      gitlab_runner_run_untagged                                   = var.runner_gitlab_registration_config["run_untagged"]
      gitlab_runner_maximum_timeout                                = var.runner_gitlab_registration_config["maximum_timeout"]
      gitlab_runner_type                                           = var.runner_gitlab_registration_config["type"]
      gitlab_runner_group_id                                       = var.runner_gitlab_registration_config["group_id"]
      gitlab_runner_project_id                                     = var.runner_gitlab_registration_config["project_id"]
      gitlab_runner_access_level                                   = var.runner_gitlab_registration_config.access_level
      sentry_dsn                                                   = var.runner_manager.sentry_dsn
      public_key                                                   = var.runner_worker.use_private_key && var.runner_worker.type == "docker-autoscaler" ? tls_private_key.autoscaler[0].public_key_openssh : var.runner_worker_docker_machine_fleet.enable == true ? tls_private_key.fleet[0].public_key_openssh : ""
      private_key                                                  = var.runner_worker.use_private_key && var.runner_worker.type == "docker-autoscaler" ? tls_private_key.autoscaler[0].private_key_pem : var.runner_worker_docker_machine_fleet.enable == true ? tls_private_key.fleet[0].private_key_pem : ""
      use_private_key                                              = var.runner_worker_docker_machine_fleet.enable || (var.runner_worker.use_private_key && var.runner_worker.type == "docker-autoscaler")
      use_new_fleeting_install                                     = local.runner_use_new_fleeting_install
      use_new_runner_authentication_gitlab_16                      = var.runner_gitlab_registration_config.type != ""
      user_data_trace_log                                          = var.debug.trace_runner_user_data
      fleeting_plugin_version                                      = var.runner_worker_docker_autoscaler.fleeting_plugin_version
  })

  template_runner_docker_autoscaler = templatefile("${path.module}/template/runner-docker-autoscaler-config.tftpl",
    {
      fleeting_plugin               = local.runner_use_new_fleeting_install ? "aws:latest" : "fleeting-plugin-aws"
      docker_autoscaling_name       = var.runner_worker.type == "docker-autoscaler" ? aws_autoscaling_group.autoscaler[0].name : ""
      connector_config_user         = var.runner_worker_docker_autoscaler.connector_config_user
      runners_capacity_per_instance = var.runner_worker_docker_autoscaler.capacity_per_instance
      runners_max_use_count         = var.runner_worker_docker_autoscaler.max_use_count
      runners_max_instances         = var.runner_worker.max_jobs

      runners_update_interval                = var.runner_worker_docker_autoscaler.update_interval
      runners_update_interval_when_expecting = var.runner_worker_docker_autoscaler.update_interval_when_expecting

      runners_instance_ready_command = var.runner_worker_docker_autoscaler.instance_ready_command

      use_private_key = var.runner_worker.use_private_key && var.runner_worker.type == "docker-autoscaler"

      runners_autoscaling = [for config in var.runner_worker_docker_autoscaler_autoscaling_options : {
        for key, value in config :
        key => jsonencode(value) if value != null
      }]
  })

  template_runner_config = templatefile("${path.module}/template/runner-config.tftpl",
    {
      aws_region       = data.aws_region.current.region
      gitlab_url       = var.runner_gitlab.url
      gitlab_clone_url = var.runner_gitlab.url_clone
      tls_ca_file      = length(var.runner_gitlab.certificate) > 0 ? "tls-ca-file=\"/etc/gitlab-runner/certs/gitlab.crt\"" : ""
      runners_machine_autoscaling = [for config in var.runner_worker_docker_machine_autoscaling_options : {
        for key, value in config :
        join("", [for subkey in split("_", key) : title(subkey)]) => jsonencode(value) if value != null
      }]

      runners_name                   = var.runner_instance.name
      runners_token                  = var.runner_gitlab.registration_token
      runners_executor               = var.runner_worker.type
      runners_limit                  = var.runner_worker.type == "docker-autoscaler" ? var.runner_worker.max_jobs * var.runner_worker_docker_autoscaler.capacity_per_instance : var.runner_worker.max_jobs
      runners_concurrent             = var.runner_manager.maximum_concurrent_jobs
      runners_environment_vars       = jsonencode(var.runner_worker.environment_variables)
      runners_pre_build_script       = var.runner_worker_gitlab_pipeline.pre_build_script
      runners_post_build_script      = var.runner_worker_gitlab_pipeline.post_build_script
      runners_pre_clone_script       = var.runner_worker_gitlab_pipeline.pre_clone_script
      runners_request_concurrency    = var.runner_worker.request_concurrency
      runners_output_limit           = var.runner_worker.output_limit
      runners_check_interval         = var.runner_manager.gitlab_check_interval
      runners_volumes_tmpfs          = join("\n", [for v in var.runner_worker_docker_volumes_tmpfs : format("\"%s\" = \"%s\"", v.volume, v.options)])
      runners_services_volumes_tmpfs = join("\n", [for v in var.runner_worker_docker_services_volumes_tmpfs : format("\"%s\" = \"%s\"", v.volume, v.options)])
      runners_docker_services        = local.runners_docker_services
      runners_docker_options         = local.runners_docker_options_toml
      bucket_name                    = local.bucket_name
      shared_cache                   = var.runner_worker_cache.shared
      sentry_dsn                     = var.runner_manager.sentry_dsn
      prometheus_listen_address      = var.runner_manager.prometheus_listen_address
      connection_max_age             = var.runner_manager.connection_max_age
      auth_type                      = var.runner_worker_cache.authentication_type
      runners_docker_autoscaler      = var.runner_worker.type == "docker-autoscaler" ? local.template_runner_docker_autoscaler : ""
      runners_docker_machine         = var.runner_worker.type == "docker+machine" ? local.template_runner_docker_machine : ""
    }
  )
}

resource "aws_autoscaling_group" "gitlab_runner_instance" {
  name                      = var.runner_enable_asg_recreation ? "${aws_launch_template.gitlab_runner_instance.name}-asg" : "${var.environment}-as-group"
  vpc_zone_identifier       = length(var.runner_worker_docker_machine_instance.subnet_ids) > 0 ? var.runner_worker_docker_machine_instance.subnet_ids : length(var.runner_worker_docker_autoscaler_asg.subnet_ids) > 0 ? var.runner_worker_docker_autoscaler_asg.subnet_ids : [var.subnet_id]
  min_size                  = "1"
  max_size                  = "1"
  desired_capacity          = "1"
  health_check_grace_period = 0
  max_instance_lifetime     = var.runner_instance.max_lifetime_seconds
  enabled_metrics           = var.runner_instance.collect_autoscaling_metrics

  dynamic "tag" {
    for_each = local.agent_tags

    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }

  launch_template {
    id      = aws_launch_template.gitlab_runner_instance.id
    version = aws_launch_template.gitlab_runner_instance.latest_version
  }

  instance_maintenance_policy {
    max_healthy_percentage = 110
    min_healthy_percentage = 100
  }

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 100
    }
    triggers = ["tag"]
  }

  timeouts {
    delete = var.runner_terraform_timeout_delete_asg
  }
  lifecycle {
    ignore_changes = [min_size, max_size, desired_capacity]
  }
}

resource "aws_autoscaling_schedule" "scale_in" {
  count                  = var.runner_schedule_enable ? 1 : 0
  autoscaling_group_name = aws_autoscaling_group.gitlab_runner_instance.name
  scheduled_action_name  = "scale_in-${aws_autoscaling_group.gitlab_runner_instance.name}"
  recurrence             = var.runner_schedule_config["scale_in_recurrence"]
  time_zone              = try(var.runner_schedule_config["scale_in_time_zone"], "Etc/UTC")
  min_size               = try(var.runner_schedule_config["scale_in_min_size"], var.runner_schedule_config["scale_in_count"])
  desired_capacity       = try(var.runner_schedule_config["scale_in_desired_capacity"], var.runner_schedule_config["scale_in_count"])
  max_size               = try(var.runner_schedule_config["scale_in_max_size"], var.runner_schedule_config["scale_in_count"])
}

resource "aws_autoscaling_schedule" "scale_out" {
  count                  = var.runner_schedule_enable ? 1 : 0
  autoscaling_group_name = aws_autoscaling_group.gitlab_runner_instance.name
  scheduled_action_name  = "scale_out-${aws_autoscaling_group.gitlab_runner_instance.name}"
  recurrence             = var.runner_schedule_config["scale_out_recurrence"]
  time_zone              = try(var.runner_schedule_config["scale_out_time_zone"], "Etc/UTC")
  min_size               = try(var.runner_schedule_config["scale_out_min_size"], var.runner_schedule_config["scale_out_count"])
  desired_capacity       = try(var.runner_schedule_config["scale_out_desired_capacity"], var.runner_schedule_config["scale_out_count"])
  max_size               = try(var.runner_schedule_config["scale_out_max_size"], var.runner_schedule_config["scale_out_count"])
}

resource "aws_launch_template" "gitlab_runner_instance" {
  name_prefix = "${local.name_runner_agent_instance}-"

  image_id               = length(var.runner_ami_id) > 0 ? var.runner_ami_id : data.aws_ami.runner_by_filter[0].id
  user_data              = base64gzip(local.template_user_data)
  instance_type          = var.runner_instance.type
  update_default_version = true
  ebs_optimized          = var.runner_instance.ebs_optimized
  monitoring {
    enabled = var.runner_instance.monitoring
  }
  dynamic "instance_market_options" {
    for_each = var.runner_instance.spot_price == null || var.runner_instance.spot_price == "" ? [] : ["spot"]
    content {
      market_type = instance_market_options.value
      dynamic "spot_options" {
        for_each = var.runner_instance.spot_price == "on-demand-price" ? [] : [0]
        content {
          max_price = var.runner_instance.spot_price
        }
      }
    }
  }
  iam_instance_profile {
    name = local.aws_iam_role_instance_name
  }
  dynamic "block_device_mappings" {
    for_each = [var.runner_instance.root_device_config]
    content {
      device_name = lookup(block_device_mappings.value, "device_name", "/dev/xvda")
      ebs {
        delete_on_termination = lookup(block_device_mappings.value, "delete_on_termination", true)
        volume_type           = lookup(block_device_mappings.value, "volume_type", "gp3")
        volume_size           = lookup(block_device_mappings.value, "volume_size", 8)
        encrypted             = lookup(block_device_mappings.value, "encrypted", true)
        iops                  = lookup(block_device_mappings.value, "iops", null)
        throughput            = lookup(block_device_mappings.value, "throughput", null)
        kms_key_id            = lookup(block_device_mappings.value, "kms_key_id", null)
      }
    }
  }
  network_interfaces {
    security_groups             = concat([aws_security_group.runner.id], var.runner_networking.security_group_ids)
    associate_public_ip_address = false == (var.runner_instance.private_address_only == false ? var.runner_instance.private_address_only : var.runner_worker_docker_machine_instance.private_address_only)
  }
  tag_specifications {
    resource_type = "instance"
    tags          = local.tags
  }
  tag_specifications {
    resource_type = "volume"
    tags          = local.tags
  }
  tag_specifications {
    resource_type = "network-interface"
    tags          = local.tags
  }
  dynamic "tag_specifications" {
    for_each = var.runner_instance.spot_price == null || var.runner_instance.spot_price == "" ? [] : ["spot"]
    content {
      resource_type = "spot-instances-request"
      tags          = local.tags
    }
  }

  tags = local.tags

  metadata_options {
    http_endpoint               = var.runner_metadata_options.http_endpoint
    http_tokens                 = var.runner_metadata_options.http_tokens
    http_put_response_hop_limit = var.runner_metadata_options.http_put_response_hop_limit
    instance_metadata_tags      = var.runner_metadata_options.instance_metadata_tags
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [aws_cloudwatch_log_group.environment]
}

locals {
  bucket_name   = var.runner_worker_cache["create"] ? module.cache[0].bucket : var.runner_worker_cache["bucket"]
  bucket_policy = var.runner_worker_cache["create"] ? module.cache[0].policy_arn : var.runner_worker_cache["policy"]
}

module "cache" {
  count  = var.runner_worker_cache["create"] ? 1 : 0
  source = "./modules/cache"

  environment = var.environment
  tags        = local.tags

  cache_bucket_prefix                  = var.runner_worker_cache.bucket_prefix
  cache_bucket_name_include_account_id = var.runner_worker_cache.include_account_id
  cache_bucket_set_random_suffix       = var.runner_worker_cache.random_suffix
  cache_bucket_versioning              = var.runner_worker_cache.versioning
  cache_expiration_days                = var.runner_worker_cache.expiration_days
  cache_lifecycle_prefix               = var.runner_worker_cache.shared ? "project/" : "runner/"
  cache_logging_bucket                 = var.runner_worker_cache.access_log_bucket_id
  cache_logging_bucket_prefix          = var.runner_worker_cache.access_log_bucket_prefix

  kms_key_id = local.kms_key_arn

  name_iam_objects = local.name_iam_objects

  create_aws_s3_bucket_public_access_block = var.runner_worker_cache.create_aws_s3_bucket_public_access_block
}

resource "aws_iam_instance_profile" "instance" {
  count = var.runner_role.create_role_profile ? 1 : 0

  name = local.aws_iam_role_instance_name
  role = local.aws_iam_role_instance_name

  tags = local.tags
}

resource "aws_eip" "gitlab_runner" {
  count = var.runner_instance.use_eip ? 1 : 0

  tags = local.tags
}

resource "aws_autoscaling_lifecycle_hook" "wait_for_gitlab_runner" {
  name                   = "${var.environment}-wait-for-gitlab-runner-up"
  autoscaling_group_name = aws_autoscaling_group.gitlab_runner_instance.name
  default_result         = "CONTINUE"
  heartbeat_timeout      = 300
  lifecycle_transition   = "autoscaling:EC2_INSTANCE_LAUNCHING"
}

module "terminate_agent_hook" {
  source = "./modules/terminate-agent-hook"

  name                                   = var.runner_terminate_ec2_lifecycle_hook_name == null ? "terminate-instances" : var.runner_terminate_ec2_lifecycle_hook_name
  environment                            = var.environment
  asg_arn                                = aws_autoscaling_group.gitlab_runner_instance.arn
  asg_name                               = aws_autoscaling_group.gitlab_runner_instance.name
  timeout                                = var.runner_terminate_ec2_timeout_duration
  cloudwatch_logging_retention_in_days   = var.runner_cloudwatch.retention_days
  name_iam_objects                       = local.name_iam_objects
  name_docker_machine_runners            = local.runner_tags_merged["Name"]
  role_permissions_boundary              = var.iam_permissions_boundary == "" ? null : "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:policy/${var.iam_permissions_boundary}"
  kms_key_id                             = local.kms_key_arn
  asg_hook_terminating_heartbeat_timeout = local.runner_worker_graceful_terminate_heartbeat_timeout
  environment_variables                  = var.runner_terminate_ec2_environment_variables
  lambda_handler                         = var.runner_terminate_ec2_lambda_handler
  layer_arns                             = var.runner_terminate_ec2_lambda_layer_arns
  egress_rules                           = var.runner_terminate_ec2_lambda_egress_rules
  vpc_id                                 = var.vpc_id
  subnet_id                              = var.subnet_id

  tags = local.tags
}

output "runner_as_group_name" {
  description = "Name of the autoscaling group for the gitlab-runner instance"
  value       = aws_autoscaling_group.gitlab_runner_instance.name
}

output "runner_cache_bucket_arn" {
  description = "ARN of the S3 for the build cache."
  value       = length(module.cache) > 0 ? module.cache[0].arn : null
}

output "runner_cache_bucket_name" {
  description = "Name of the S3 for the build cache."
  value       = length(module.cache) > 0 ? module.cache[0].bucket : null
}

output "runner_agent_role_arn" {
  description = "ARN of the role used for the ec2 instance for the GitLab runner agent."
  value       = local.aws_iam_role_instance_arn
}

output "runner_agent_role_name" {
  description = "Name of the role used for the ec2 instance for the GitLab runner agent."
  value       = local.aws_iam_role_instance_name
}

output "runner_role_arn" {
  description = "ARN of the role used for the docker machine runners."
  value       = length(aws_iam_role.docker_machine) > 0 ? aws_iam_role.docker_machine[0].arn : (length(aws_iam_role.docker_autoscaler) > 0 ? aws_iam_role.docker_autoscaler[0].arn : null)
}

output "runner_role_name" {
  description = "Name of the role used for the docker machine runners."
  value       = length(aws_iam_role.docker_machine) > 0 ? aws_iam_role.docker_machine[0].name : (length(aws_iam_role.docker_autoscaler) > 0 ? aws_iam_role.docker_autoscaler[0].name : null)
}

output "runner_agent_sg_id" {
  description = "ID of the security group attached to the GitLab runner agent."
  value       = aws_security_group.runner.id
}

output "runner_sg_id" {
  description = "ID of the security group attached to the worker instances (docker machine/autoscaler runners)."
  value       = var.runner_worker.type == "docker-autoscaler" ? aws_security_group.docker_autoscaler[0].id : (var.runner_worker.type == "docker+machine" ? aws_security_group.docker_machine[0].id : null)
}

output "runner_eip" {
  description = "EIP of the Gitlab Runner"
  value       = length(aws_eip.gitlab_runner) > 0 ? aws_eip.gitlab_runner[0].public_ip : null
}

output "runner_launch_template_name" {
  description = "The name of the runner's launch template."
  value       = aws_launch_template.gitlab_runner_instance.name
}

resource "aws_iam_role" "instance" {
  count = var.runner_role.create_role_profile ? 1 : 0

  name                 = local.aws_iam_role_instance_name
  assume_role_policy   = length(var.runner_role.assume_role_policy_json) > 0 ? var.runner_role.assume_role_policy_json : templatefile("${path.module}/policies/instance-role-trust-policy.json", {})
  permissions_boundary = var.iam_permissions_boundary == "" ? null : "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:policy/${var.iam_permissions_boundary}"

  tags = merge(local.tags, var.runner_role.additional_tags)
}

resource "aws_iam_policy" "instance_kms_policy" {
  count = var.enable_managed_kms_key ? 1 : 0

  name        = "${local.name_iam_objects}-kms"
  path        = "/"
  description = "Allow runner instance the ability to use the KMS key."
  policy = templatefile("${path.module}/policies/instance-kms-policy.json",
    {
      kms_key_arn = local.kms_key_arn
    }
  )

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "instance_kms_policy" {
  count = var.enable_managed_kms_key ? 1 : 0

  role       = var.runner_role.create_role_profile ? aws_iam_role.instance[0].name : local.aws_iam_role_instance_name
  policy_arn = aws_iam_policy.instance_kms_policy[0].arn
}

resource "aws_iam_policy" "instance_session_manager_policy" {
  count = var.runner_instance.ssm_access ? 1 : 0

  name        = "${local.name_iam_objects}-session-manager"
  path        = "/"
  description = "Policy session manager."
  policy      = templatefile("${path.module}/policies/instance-session-manager-policy.json", {})

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "instance_session_manager_policy" {
  count = var.runner_instance.ssm_access ? 1 : 0

  role       = var.runner_role.create_role_profile ? aws_iam_role.instance[0].name : local.aws_iam_role_instance_name
  policy_arn = aws_iam_policy.instance_session_manager_policy[0].arn
}

resource "aws_iam_role_policy_attachment" "instance_session_manager_aws_managed" {
  count = var.runner_instance.ssm_access ? 1 : 0

  role       = var.runner_role.create_role_profile ? aws_iam_role.instance[0].name : local.aws_iam_role_instance_name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "user_defined_policies" {
  count = length(var.runner_role.policy_arns)

  role       = var.runner_role.create_role_profile ? aws_iam_role.instance[0].name : local.aws_iam_role_instance_name
  policy_arn = var.runner_role.policy_arns[count.index]
}

resource "aws_iam_role_policy_attachment" "docker_machine_cache_instance" {
  count = var.runner_worker_cache["create"] || lookup(var.runner_worker_cache, "policy", "") != "" ? 1 : 0

  role       = var.runner_role.create_role_profile ? aws_iam_role.instance[0].name : local.aws_iam_role_instance_name
  policy_arn = local.bucket_policy
}

resource "aws_iam_policy" "service_linked_role" {
  count = var.runner_role.allow_iam_service_linked_role_creation ? 1 : 0

  name        = "${local.name_iam_objects}-service_linked_role"
  path        = "/"
  description = "Policy for creation of service linked roles."
  policy      = templatefile("${path.module}/policies/service-linked-role-create-policy.json", { partition = data.aws_partition.current.partition })

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "service_linked_role" {
  count = var.runner_role.allow_iam_service_linked_role_creation ? 1 : 0

  role       = var.runner_role.create_role_profile ? aws_iam_role.instance[0].name : local.aws_iam_role_instance_name
  policy_arn = aws_iam_policy.service_linked_role[0].arn
}

data "aws_iam_policy_document" "ssm" {
  statement {
    actions = [
      "ssm:GetParameter",
      "ssm:GetParameters",
    ]
    resources = [
      for name in compact(
        [
          aws_ssm_parameter.runner_sentry_dsn.name,
          var.runner_gitlab_registration_token_secure_parameter_store_name,
          var.runner_gitlab.access_token_secure_parameter_store_name,
          var.runner_gitlab.preregistered_runner_token_ssm_parameter_name,
          aws_ssm_parameter.runner_registration_token.name
        ]
      ) : "arn:${data.aws_partition.current.partition}:ssm:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:parameter/${trimprefix(name, "/")}"
    ]
  }

  statement {
    actions = ["ssm:PutParameter"]
    resources = [
      "arn:${data.aws_partition.current.partition}:ssm:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:parameter/${trimprefix(aws_ssm_parameter.runner_registration_token.name, "/")}"
    ]
  }
}

resource "aws_iam_policy" "ssm" {
  name        = "${local.name_iam_objects}-ssm"
  path        = "/"
  description = "Policy for runner token param access via SSM"
  policy      = data.aws_iam_policy_document.ssm.json

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = var.runner_role.create_role_profile ? aws_iam_role.instance[0].name : local.aws_iam_role_instance_name
  policy_arn = aws_iam_policy.ssm.arn
}

resource "aws_iam_policy" "eip" {
  count = var.runner_instance.use_eip ? 1 : 0

  name        = "${local.name_iam_objects}-eip"
  path        = "/"
  description = "Policy for runner to assign EIP"
  policy      = templatefile("${path.module}/policies/instance-eip.json", {})

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "eip" {
  count = var.runner_instance.use_eip ? 1 : 0

  role       = var.runner_role.create_role_profile ? aws_iam_role.instance[0].name : local.aws_iam_role_instance_name
  policy_arn = aws_iam_policy.eip[0].arn
}

resource "aws_security_group" "runner" {
  name_prefix = local.name_sg
  vpc_id      = var.vpc_id
  description = var.runner_networking.security_group_description

  tags = merge(
    local.tags,
    {
      "Name" = format("%s", local.name_sg)
    },
  )
}

resource "aws_vpc_security_group_ingress_rule" "runner" {
  for_each = var.runner_ingress_rules

  security_group_id = aws_security_group.runner.id

  from_port   = each.value.from_port
  to_port     = each.value.to_port
  ip_protocol = each.value.protocol

  description                  = each.value.description
  prefix_list_id               = each.value.prefix_list_id
  referenced_security_group_id = each.value.security_group
  cidr_ipv4                    = each.value.cidr_block
  cidr_ipv6                    = each.value.ipv6_cidr_block

  tags = local.tags
}

resource "aws_vpc_security_group_egress_rule" "runner" {
  for_each = var.runner_egress_rules

  security_group_id = aws_security_group.runner.id

  from_port   = each.value.from_port
  to_port     = each.value.to_port
  ip_protocol = each.value.protocol

  description                  = each.value.description
  prefix_list_id               = each.value.prefix_list_id
  referenced_security_group_id = each.value.security_group
  cidr_ipv4                    = each.value.cidr_block
  cidr_ipv6                    = each.value.ipv6_cidr_block

  tags = local.tags
}

resource "aws_vpc_security_group_egress_rule" "runner_manager_to_docker_autoscaler_egress" {
  count = var.runner_worker.type == "docker-autoscaler" ? 1 : 0

  security_group_id = aws_security_group.runner.id

  ip_protocol                  = "-1"
  description                  = "Allow ALL Egress traffic between Runner Manager and Docker-autoscaler workers security group"
  referenced_security_group_id = aws_security_group.docker_autoscaler[0].id

  tags = local.tags
}

resource "aws_vpc_security_group_egress_rule" "runner_manager_to_docker_machine_egress" {
  count = var.runner_worker.type == "docker+machine" ? 1 : 0

  security_group_id = aws_security_group.runner.id

  ip_protocol                  = "-1"
  description                  = "Allow ALL Egress traffic between Runner Manager and Docker-machine workers security group"
  referenced_security_group_id = aws_security_group.docker_machine[0].id

  tags = local.tags
}

resource "aws_vpc_security_group_ingress_rule" "runner_ping_group" {
  count = length(var.runner_networking.allow_incoming_ping_security_group_ids) > 0 && var.runner_networking.allow_incoming_ping ? length(var.runner_networking.allow_incoming_ping_security_group_ids) : 0

  from_port   = -1
  to_port     = -1
  ip_protocol = "icmp"

  referenced_security_group_id = element(var.runner_networking.allow_incoming_ping_security_group_ids, count.index)
  security_group_id            = aws_security_group.runner.id

  description = format(
    "Allow ICMP traffic from %s to gitlab-runner agent instances in group %s",
    element(var.runner_networking.allow_incoming_ping_security_group_ids, count.index),
    aws_security_group.runner.name
  )
}

locals {
  tags_merged = merge(
    {
      "Name" = format("%s", var.environment)
    },
    {
      "Environment" = format("%s", var.environment)
    },
    var.tags,
  )

  tags = { for k, v in local.tags_merged : k => v if !contains(var.suppressed_tags, k) }

  agent_tags_merged = merge(
    {
      "Name" = format("%s", local.name_runner_agent_instance)
    },
    {
      "Environment" = format("%s", var.environment)
    },
    var.tags,
    var.runner_instance.additional_tags
  )

  agent_tags = { for k, v in local.agent_tags_merged : k => v if !contains(var.suppressed_tags, k) }

  runner_tags_merged = merge(
    local.tags,
    var.runner_worker_docker_machine_role.additional_tags,
    var.runner_worker_docker_machine_instance.name_prefix == "" ? { Name = substr(format("%s", var.environment), 0, 16) } : { Name = var.runner_worker_docker_machine_instance.name_prefix },
  )

  runner_tags = local.docker_machine_adds_name_tag ? { for k, v in local.runner_tags_merged : k => v if !contains(concat(var.suppressed_tags, ["Name"]), k) } : local.runner_tags_merged

  runner_tags_string = join(",", flatten([
    for key in keys(local.runner_tags) : [key, local.runner_tags[key]]
  ]))
}

variable "vpc_id" {
  description = "The VPC used for the runner and runner workers."
  type        = string
}

variable "subnet_id" {
  description = <<-EOT
    Subnet id used for the Runner and Runner Workers. Must belong to the `vpc_id`. In case the fleet mode is used, multiple subnets for
    the Runner Workers can be provided with runner_worker_docker_machine_instance.subnet_ids.
  EOT
  type        = string
}

variable "kms_key_id" {
  description = "KMS key id to encrypt the resources. Ensure that CloudWatch and Runner/Runner Workers have access to the provided KMS key."
  type        = string
  default     = ""
}

variable "enable_managed_kms_key" {
  description = "Let the module manage a KMS key. Be-aware of the costs of an custom key. Do not specify a `kms_key_id` when `enable_kms` is set to `true`."
  type        = bool
  default     = false
}

variable "kms_managed_alias_name" {
  description = "Alias added to the created KMS key."
  type        = string
  default     = ""
}

variable "kms_managed_deletion_rotation_window_in_days" {
  description = "Key deletion/rotation window for the created KMS key. Set to 0 for no rotation/deletion window."
  type        = number
  default     = 7
}

variable "iam_permissions_boundary" {
  description = "Name of permissions boundary policy to attach to AWS IAM roles"
  type        = string
  default     = ""
}

variable "environment" {
  description = "A name that identifies the environment, used as prefix and for tagging."
  type        = string

  validation {
    condition     = !startswith(var.environment, "runner-")
    error_message = "Environment name cannot begin with 'runner-' because it breaks the naming convention for ssh key pairs within the terminate-agent-hook lambda function."
  }
}

variable "tags" {
  description = "Map of tags that will be added to created resources. By default resources will be tagged with name and environment."
  type        = map(string)
  default     = {}
}

variable "suppressed_tags" {
  description = "List of tag keys which are automatically removed and never added as default tag by the module."
  type        = list(string)
  default     = []
}

variable "security_group_prefix" {
  description = "Set the name prefix and overwrite the `Name` tag for all security groups."
  type        = string
  default     = ""
}

variable "iam_object_prefix" {
  description = "Set the name prefix of all AWS IAM resources."
  type        = string
  default     = ""
}

variable "runner_manager" {
  description = <<-EOT
    For details check https://docs.gitlab.com/runner/configuration/advanced-configuration.html#the-global-section

    gitlab_check_interval = Number of seconds between checking for available jobs (check_interval)
    maximum_concurrent_jobs = The maximum number of jobs which can be processed by all Runners at the same time (concurrent).
    prometheus_listen_address = Defines an address (<host>:<port>) the Prometheus metrics HTTP server should listen on (listen_address).
    sentry_dsn = Sentry DSN of the project for the Runner Manager to use (uses legacy DSN format) (sentry_dsn)
    connection_max_age = The maximum age of a connection to the Runner Manager (connection_max_age).
  EOT
  type = object({
    gitlab_check_interval     = optional(number, 3)
    maximum_concurrent_jobs   = optional(number, 10)
    prometheus_listen_address = optional(string, "")
    sentry_dsn                = optional(string, "__SENTRY_DSN_REPLACED_BY_USER_DATA__")
    connection_max_age        = optional(string, "15m")
  })
  default = {}
}

variable "runner_instance" {
  description = <<-EOT
    additional_tags = Map of tags that will be added to the Runner instance.
    collect_autoscaling_metrics = A list of metrics to collect. The allowed values are GroupDesiredCapacity, GroupInServiceCapacity, GroupPendingCapacity, GroupMinSize, GroupMaxSize, GroupInServiceInstances, GroupPendingInstances, GroupStandbyInstances, GroupStandbyCapacity, GroupTerminatingCapacity, GroupTerminatingInstances, GroupTotalCapacity, GroupTotalInstances.
    ebs_optimized = Enable EBS optimization for the Runner instance.
    max_lifetime_seconds = The maximum time a Runner should live before it is killed.
    monitoring = Enable the detailed monitoring on the Runner instance.
    name = Name of the Runner instance.
    name_prefix = Set the name prefix and override the `Name` tag for the Runner instance.
    private_address_only = Restrict the Runner to use private IP addresses only. If this is set to `true` the Runner will use a private IP address only in case the Runner Workers use private addresses only.
    root_device_config = The Runner's root block device configuration. Takes the following keys: `device_name`, `delete_on_termination`, `volume_type`, `volume_size`, `encrypted`, `iops`, `throughput`, `kms_key_id`
    spot_price = By setting a spot price bid price the Runner is created via a spot request. Be aware that spot instances can be stopped by AWS. Choose \"on-demand-price\" to pay up to the current on demand price for the instance type chosen.
    ssm_access = Allows to connect to the Runner via SSM.
    type = EC2 instance type used.
    use_eip = Assigns an EIP to the Runner.
  EOT
  type = object({
    additional_tags             = optional(map(string))
    collect_autoscaling_metrics = optional(list(string), null)
    ebs_optimized               = optional(bool, true)
    max_lifetime_seconds        = optional(number, null)
    monitoring                  = optional(bool, true)
    name                        = string
    name_prefix                 = optional(string)
    private_address_only        = optional(bool, true)
    root_device_config          = optional(map(string), {})
    spot_price                  = optional(string, null)
    ssm_access                  = optional(bool, false)
    type                        = optional(string, "t3.micro")
    use_eip                     = optional(bool, false)
  })
  default = {
    name = "gitlab-runner"
  }
}

variable "runner_ami_filter" {
  description = "List of maps used to create the AMI filter for the Runner AMI. Must resolve to an Amazon Linux 1, 2 or 2023 image."
  type        = map(list(string))

  default = {
    name = ["al2023-ami-2023*-x86_64"]
  }
}

variable "runner_ami_owners" {
  description = "The list of owners used to select the AMI of the Runner instance."
  type        = list(string)
  default     = ["amazon"]
}

variable "runner_ami_id" {
  description = "The AMI ID of the Runner instance."
  type        = string
  default     = ""
}

variable "runner_networking" {
  description = <<-EOT
    allow_incoming_ping = Allow ICMP Ping to the Runner. Specify `allow_incoming_ping_security_group_ids` too!
    allow_incoming_ping_security_group_ids = A list of security group ids that are allowed to ping the Runner.
    security_group_description = A description for the Runner's security group
    security_group_ids = IDs of security groups to add to the Runner.
  EOT
  type = object({
    allow_incoming_ping                    = optional(bool, false)
    allow_incoming_ping_security_group_ids = optional(list(string), [])
    security_group_description             = optional(string, "A security group containing gitlab-runner agent instances")
    security_group_ids                     = optional(list(string), [])
  })
  default = {}
}

variable "runner_ingress_rules" {
  description = "Map of Ingress rules for the Runner Manager security group."
  type = map(object({
    from_port       = optional(number, null)
    to_port         = optional(number, null)
    protocol        = string
    description     = string
    cidr_block      = optional(string, null)
    ipv6_cidr_block = optional(string, null)
    prefix_list_id  = optional(string, null)
    security_group  = optional(string, null)
  }))
  default = {}

  validation {
    condition = alltrue([
      for rule in values(var.runner_ingress_rules) :
      contains(["-1", "tcp", "udp", "icmp", "icmpv6"], rule.protocol)
    ])
    error_message = "Protocol must be '-1', 'tcp', 'udp', 'icmp', or 'icmpv6'."
  }

  validation {
    condition = alltrue([
      for rule in values(var.runner_ingress_rules) :
      (rule.cidr_block != null) ||
      (rule.ipv6_cidr_block != null) ||
      (rule.prefix_list_id != null) ||
      (rule.security_group != null)
    ])
    error_message = "At least one destination must be specified."
  }
}

variable "runner_egress_rules" {
  description = "Map of Egress rules for the Runner Manager security group."
  type = map(object({
    from_port       = optional(number, null)
    to_port         = optional(number, null)
    protocol        = string
    description     = string
    cidr_block      = optional(string, null)
    ipv6_cidr_block = optional(string, null)
    prefix_list_id  = optional(string, null)
    security_group  = optional(string, null)
  }))
  default = {}

  validation {
    condition = alltrue([
      for rule in values(var.runner_egress_rules) :
      contains(["-1", "tcp", "udp", "icmp", "icmpv6"], rule.protocol)
    ])
    error_message = "Protocol must be '-1', 'tcp', 'udp', 'icmp', or 'icmpv6'."
  }

  validation {
    condition = alltrue([
      for rule in values(var.runner_egress_rules) :
      (rule.cidr_block != null) ||
      (rule.ipv6_cidr_block != null) ||
      (rule.prefix_list_id != null) ||
      (rule.security_group != null)
    ])
    error_message = "At least one destination must be specified."
  }
}

variable "runner_role" {
  description = <<-EOT
        additional_tags = Map of tags that will be added to the role created. Useful for tag based authorization.
        allow_iam_service_linked_role_creation = Boolean used to control attaching the policy to the Runner to create service linked roles.
        assume_role_policy_json = The assume role policy for the Runner.
        create_role_profile = Whether to create the IAM role/profile for the Runner. If you provide your own role, make sure that it has the required permissions.
        policy_arns = List of policy ARNs to be added to the instance profile of the Runner.
        role_profile_name = IAM role/profile name for the Runner. If unspecified then `$${var.iam_object_prefix}-instance` is used.
    EOT
  type = object({
    additional_tags                        = optional(map(string))
    allow_iam_service_linked_role_creation = optional(bool, true)
    assume_role_policy_json                = optional(string, "")
    create_role_profile                    = optional(bool, true)
    policy_arns                            = optional(list(string), [])
    role_profile_name                      = optional(string)
  })
  default = {}
}

variable "runner_metadata_options" {
  description = "Enable the Runner instance metadata service. IMDSv2 is enabled by default."
  type = object({
    http_endpoint               = string
    http_tokens                 = string
    http_put_response_hop_limit = number
    instance_metadata_tags      = string
  })
  default = {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
    instance_metadata_tags      = "disabled"
  }
}

variable "runner_schedule_enable" {
  description = "Set to `true` to enable the auto scaling group schedule for the Runner."
  type        = bool
  default     = false
}

variable "runner_enable_asg_recreation" {
  description = "Enable automatic redeployment of the Runner's ASG when the Launch Configs change."
  default     = true
  type        = bool
}

variable "runner_schedule_config" {
  description = "Map containing the configuration of the ASG scale-out and scale-in for the Runner. Will only be used if `runner_schedule_enable` is set to `true`. "
  type        = map(any)
  default = {
    scale_out_recurrence = "0 8 * * 1-5"
    scale_out_count      = 1
    scale_out_time_zone  = "Etc/UTC"

    scale_in_recurrence = "0 18 * * 1-5"
    scale_in_count      = 0
    scale_in_time_zone  = "Etc/UTC"
  }
}

variable "runner_install" {
  description = <<-EOT
    amazon_ecr_credential_helper = Install amazon-ecr-credential-helper inside `userdata_pre_install` script
    docker_machine_download_url = URL to download docker machine binary. If not set, the docker machine version will be used to download the binary.
    docker_machine_version = By default docker_machine_download_url is used to set the docker machine version. This version will be ignored once `docker_machine_download_url` is set. The version number is maintained by the CKI project. Check out at https://gitlab.com/cki-project/docker-machine/-/releases
    pre_install_script = Script to run before installing the Runner
    post_install_script = Script to run after installing the Runner
    start_script = Script to run after starting the Runner
    yum_update = Update the yum packages before installing the Runner
  EOT
  type = object({
    amazon_ecr_credential_helper = optional(bool, false)
    docker_machine_download_url  = optional(string, "")
    docker_machine_version       = optional(string, "0.16.2-gitlab.19-cki.5")
    pre_install_script           = optional(string, "")
    post_install_script          = optional(string, "")
    start_script                 = optional(string, "")
    yum_update                   = optional(bool, true)
  })
  default = {}
}

variable "runner_cloudwatch" {
  description = <<-EOT
    enable = Boolean used to enable or disable the CloudWatch logging.
    log_group_name = Option to override the default name (`environment`) of the log group. Requires `enable = true`.
    retention_days = Retention for cloudwatch logs. Defaults to unlimited. Requires `enable = true`.
  EOT
  type = object({
    enable         = optional(bool, true)
    log_group_name = optional(string, null)
    retention_days = optional(number, 0)
  })
  default = {}
}

variable "runner_gitlab_registration_config" {
  description = "(deprecated, replaced by runner_gitlab.preregistered_runner_token_ssm_parameter_name) Register the Runner manually with GitLab first."
  type = object({
    registration_token = optional(string, "__GITLAB_REGISTRATION_TOKEN_FROM_SSM__")
    tag_list           = optional(string, "")
    description        = optional(string, "")
    type               = optional(string, "")
    group_id           = optional(string, "")
    project_id         = optional(string, "")
    locked_to_project  = optional(string, "")
    run_untagged       = optional(string, "")
    maximum_timeout    = optional(string, "")
    access_level       = optional(string, "not_protected")
  })

  default = {}
  validation {
    condition     = contains(["group", "project", "instance", ""], var.runner_gitlab_registration_config.type)
    error_message = "The executor currently supports `group`, `project` or `instance`."
  }
}

variable "runner_gitlab" {
  description = <<-EOT
    ca_certificate = Trusted CA certificate bundle (PEM format).
    certificate = Certificate of the GitLab instance to connect to (PEM format).
    registration_token = (deprecated, this is replaced by the `preregistered_runner_token_ssm_parameter_name`) Registration token to use to register the Runner.
    runner_version = Version of the [GitLab Runner](https://gitlab.com/gitlab-org/gitlab-runner/-/releases). Make sure that it is available for your AMI. See https://packages.gitlab.com/app/runner/gitlab-runner/search?dist=amazon%2F2023&filter=rpms&page=1&q=
    url = URL of the GitLab instance to connect to.
    url_clone = URL of the GitLab instance to clone from. Use only if the agent can't connect to the GitLab URL.
    access_token_secure_parameter_store_name = (deprecated, this is replaced by the `preregistered_runner_token_ssm_parameter_name`) The name of the SSM parameter to read the GitLab access token from. It must have the `api` scope and be pre created.
    preregistered_runner_token_ssm_parameter_name = The name of the SSM parameter to read the preregistered GitLab Runner token from.
  EOT
  type = object({
    ca_certificate                                = optional(string, "")
    certificate                                   = optional(string, "")
    registration_token                            = optional(string, "__REPLACED_BY_USER_DATA__")
    runner_version                                = optional(string, "16.0.3")
    url                                           = optional(string, "")
    url_clone                                     = optional(string, "")
    access_token_secure_parameter_store_name      = optional(string, "gitlab-runner-access-token")
    preregistered_runner_token_ssm_parameter_name = optional(string, "")
  })
}

variable "runner_gitlab_registration_token_secure_parameter_store_name" {
  description = "(deprecated, replaced by runner_gitlab.preregistered_runner_token_ssm_parameter_name) The name of the SSM parameter to read the GitLab Runner registration token from."
  type        = string
  default     = "gitlab-runner-registration-token"
}

variable "runner_gitlab_token_secure_parameter_store" {
  description = "Name of the Secure Parameter Store entry to hold the GitLab Runner token."
  type        = string
  default     = "runner-token"
}

variable "runner_sentry_secure_parameter_store_name" {
  description = "The Sentry DSN name used to store the Sentry DSN in Secure Parameter Store"
  type        = string
  default     = "sentry-dsn"
}

variable "runner_terminate_ec2_lifecycle_hook_name" {
  description = "Specifies a custom name for the ASG terminate lifecycle hook and related resources."
  type        = string
  default     = null
}

variable "runner_terminate_ec2_lifecycle_timeout_duration" {
  description = "Amount of time in seconds to wait for GitLab Runner to finish picked up jobs. Defaults to the `maximum_timeout` configured + `5m`. Maximum allowed is `7200` (2 hours)"
  type        = number
  default     = null
}

variable "runner_terraform_timeout_delete_asg" {
  description = "Timeout when trying to delete the Runner ASG."
  default     = "10m"
  type        = string
}

variable "runner_terminate_ec2_timeout_duration" {
  description = "Timeout in seconds for the graceful terminate worker Lambda function."
  type        = number
  default     = 90
}

variable "runner_terminate_ec2_environment_variables" {
  description = "Environment variables to set for the Lambda function. A value of `{HANDLER} is replaced with the handler value of the Lambda function."
  type        = map(string)
  default     = {}
}

variable "runner_terminate_ec2_lambda_handler" {
  description = "The handler for the terminate Lambda function."
  type        = string
  default     = null
}

variable "runner_terminate_ec2_lambda_layer_arns" {
  description = "A list of ARNs of Lambda layers to attach to the Lambda function."
  type        = list(string)
  default     = []
}

variable "runner_terminate_ec2_lambda_egress_rules" {
  description = "Map of egress rules for the Lambda function."
  type = map(object({
    from_port       = optional(number, null)
    to_port         = optional(number, null)
    protocol        = string
    description     = string
    cidr_block      = optional(string, null)
    ipv6_cidr_block = optional(string, null)
    prefix_list_id  = optional(string, null)
    security_group  = optional(string, null)
  }))
  default = {}

  validation {
    condition = alltrue([
      for rule in values(var.runner_terminate_ec2_lambda_egress_rules) :
      contains(["-1", "tcp", "udp", "icmp", "icmpv6"], rule.protocol)
    ])
    error_message = "Protocol must be '-1', 'tcp', 'udp', 'icmp', or 'icmpv6'."
  }

  validation {
    condition = alltrue([
      for rule in values(var.runner_terminate_ec2_lambda_egress_rules) :
      (rule.cidr_block != null) ||
      (rule.ipv6_cidr_block != null) ||
      (rule.prefix_list_id != null) ||
      (rule.security_group != null)
    ])
    error_message = "At least one destination must be specified."
  }
}

variable "runner_worker" {
  description = <<-EOT
    For detailed information, check https://docs.gitlab.com/runner/configuration/advanced-configuration.html#the-runners-section.

    environment_variables = List of environment variables to add to the Runner Worker (environment).
    max_jobs = Number of jobs which can be processed in parallel by the Runner Worker.
    output_limit = Sets the maximum build log size in kilobytes. Default is 4MB (output_limit).
    request_concurrency = Limit number of concurrent requests for new jobs from GitLab (default 1) (request_concurrency).
    ssm_access = Allows to connect to the Runner Worker via SSM.
    type = The Runner Worker type to use. Currently supports `docker+machine` or `docker` or `docker-autoscaler`.
    use_private_key = Use a private key to connect the Runner Manager to the Runner Workers. Ignored when fleeting is enabled (defaults to `true`).
  EOT
  type = object({
    environment_variables = optional(list(string), [])
    max_jobs              = optional(number, 0)
    output_limit          = optional(number, 4096)
    request_concurrency   = optional(number, 1)
    ssm_access            = optional(bool, false)
    type                  = optional(string, "docker+machine")
    use_private_key       = optional(bool, false)
  })
  default = {}

  validation {
    condition     = contains(["docker+machine", "docker", "docker-autoscaler"], var.runner_worker.type)
    error_message = "The executor currently supports `docker+machine` and `docker`."
  }
}

variable "runner_worker_cache" {
  description = <<-EOT
    Configuration to control the creation of the cache bucket. By default the bucket will be created and used as shared
    cache. To use the same cache across multiple Runner Worker disable the creation of the cache and provide a policy and
    bucket name. See the public runner example for more details."

    For detailed documentation check https://docs.gitlab.com/runner/configuration/advanced-configuration.html#the-runnerscaches3-section.

    access_log_bucker_id = The ID of the bucket where the access logs are stored.
    access_log_bucket_prefix = The bucket prefix for the access logs.
    authentication_type = A string that declares the AuthenticationType for [runners.cache.s3]. Can either be 'iam' or 'credentials'.
    bucket = Name of the cache bucket. Requires `create = false`.
    bucket_prefix = Prefix for s3 cache bucket name. Requires `create = true`.
    create = Boolean used to enable or disable the creation of the cache bucket.
    create_aws_s3_bucket_public_access_block = Boolean used to enable or disable the creation of the public access block for the cache bucket. Useful when organizations do not allow the creation of public access blocks on individual buckets (e.g. public access is blocked on all buckets at the organization level).
    expiration_days = Number of days before cache objects expire. Requires `create = true`.
    include_account_id = Boolean used to include the account id in the cache bucket name. Requires `create = true`.
    policy = Policy to use for the cache bucket. Requires `create = false`.
    random_suffix = Boolean used to enable or disable the use of a random string suffix on the cache bucket name. Requires `create = true`.
    shared = Boolean used to enable or disable the use of the cache bucket as shared cache.
    versioning = Boolean used to enable versioning on the cache bucket. Requires `create = true`.
  EOT
  type = object({
    access_log_bucket_id                     = optional(string, null)
    access_log_bucket_prefix                 = optional(string, null)
    authentication_type                      = optional(string, "iam")
    bucket                                   = optional(string, "")
    bucket_prefix                            = optional(string, "")
    create                                   = optional(bool, true)
    create_aws_s3_bucket_public_access_block = optional(bool, true)
    expiration_days                          = optional(number, 1)
    include_account_id                       = optional(bool, true)
    policy                                   = optional(string, "")
    random_suffix                            = optional(bool, false)
    shared                                   = optional(bool, false)
    versioning                               = optional(bool, false)
  })
  default = {}
}

variable "runner_worker_gitlab_pipeline" {
  description = <<-EOT
    post_build_script = Script to execute in the pipeline just after the build, but before executing after_script.
    pre_build_script = Script to execute in the pipeline just before the build.
    pre_clone_script = Script to execute in the pipeline before cloning the Git repository. this can be used to adjust the Git client configuration first, for example.
  EOT
  type = object({
    post_build_script = optional(string, "\"\"")
    pre_build_script  = optional(string, "\"\"")
    pre_clone_script  = optional(string, "\"\"")
  })
  default = {}
}

variable "runner_worker_docker_volumes_tmpfs" {
  description = "Mount a tmpfs in Executor container. https://docs.gitlab.com/runner/executors/docker.html#mounting-a-directory-in-ram"
  type = list(object({
    volume  = string
    options = string
  }))
  default = []
}

variable "runner_worker_docker_services" {
  description = "Starts additional services with the Docker container. All fields must be set (examine the Dockerfile of the service image for the entrypoint - see ./examples/runner-default/main.tf)"
  type = list(object({
    name       = string
    alias      = string
    entrypoint = list(string)
    command    = list(string)
  }))
  default = []
}

variable "runner_worker_docker_services_volumes_tmpfs" {
  description = "Mount a tmpfs in gitlab service container. https://docs.gitlab.com/runner/executors/docker.html#mounting-a-directory-in-ram"
  type = list(object({
    volume  = string
    options = string
  }))
  default = []
}

variable "runner_worker_docker_add_dind_volumes" {
  description = "Add certificates and docker.sock to the volumes to support docker-in-docker (dind)"
  type        = bool
  default     = false
}

variable "runner_worker_docker_options" {
  description = <<EOT
    Options added to the [runners.docker] section of config.toml to configure the Docker container of the Runner Worker. For
    details check https://docs.gitlab.com/runner/configuration/advanced-configuration.html

    Default values if the option is not given:
      disable_cache = "false"
      image         = "docker:18.03.1-ce"
      privileged    = "true"
      pull_policy   = "always"
      shm_size      = 0
      tls_verify    = "false"
      volumes       = "/cache"
  EOT

  type = object({
    allowed_images               = optional(list(string))
    allowed_pull_policies        = optional(list(string))
    allowed_services             = optional(list(string))
    cache_dir                    = optional(string)
    cap_add                      = optional(list(string))
    cap_drop                     = optional(list(string))
    container_labels             = optional(list(string))
    cpuset_cpus                  = optional(string)
    cpu_shares                   = optional(number)
    cpus                         = optional(string)
    devices                      = optional(list(string))
    device_cgroup_rules          = optional(list(string))
    disable_cache                = optional(bool, false)
    disable_entrypoint_overwrite = optional(bool)
    dns                          = optional(list(string))
    dns_search                   = optional(list(string))
    extra_hosts                  = optional(list(string))
    gpus                         = optional(string)
    helper_image                 = optional(string)
    helper_image_flavor          = optional(string)
    host                         = optional(string)
    hostname                     = optional(string)
    image                        = optional(string, "docker:18.03.1-ce")
    isolation                    = optional(string)
    links                        = optional(list(string))
    mac_address                  = optional(string)
    memory                       = optional(string)
    memory_swap                  = optional(string)
    memory_reservation           = optional(string)
    network_mode                 = optional(string)
    oom_kill_disable             = optional(bool)
    oom_score_adjust             = optional(number)
    privileged                   = optional(bool, true)
    pull_policies                = optional(list(string), ["always"])
    runtime                      = optional(string)
    security_opt                 = optional(list(string))
    shm_size                     = optional(number, 0)
    sysctls                      = optional(list(string))
    tls_cert_path                = optional(string)
    tls_verify                   = optional(bool, false)
    user                         = optional(string)
    userns_mode                  = optional(string)
    volumes                      = optional(list(string), ["/cache"])
    volumes_from                 = optional(list(string))
    volume_driver                = optional(string)
    wait_for_services_timeout    = optional(number)
  })

  default = {
    disable_cache = "false"
    image         = "docker:18.03.1-ce"
    privileged    = "true"
    pull_policies = ["always"]
    shm_size      = 0
    tls_verify    = "false"
    volumes       = ["/cache"]
  }
}

variable "runner_worker_docker_machine_fleet" {
  description = <<-EOT
    enable = Activates the fleet mode on the Runner. https://gitlab.com/cki-project/docker-machine/-/blob/v0.16.2-gitlab.19-cki.2/docs/drivers/aws.md#fleet-mode
    key_pair_name = The name of the key pair used by the Runner to connect to the docker-machine Runner Workers. This variable is only supported when `enables` is set to `true`.
  EOT
  type = object({
    enable        = bool
    key_pair_name = optional(string, "fleet-key")
  })
  default = {
    enable = false
  }
}

variable "runner_worker_docker_autoscaler" {
  description = <<-EOT
    fleeting_plugin_version = The version of aws fleeting plugin.
    connector_config_user = User to connect to worker machine.
    key_pair_name = The name of the key pair used by the Runner to connect to the docker-machine Runner Workers. This variable is only supported when `enables` is set to `true`.
    capacity_per_instance = The number of jobs that can be executed concurrently by a single instance.
    max_use_count = Max job number that can run on a worker.
    update_interval = The interval to check with the fleeting plugin for instance updates.
    update_interval_when_expecting = The interval to check with the fleeting plugin for instance updates when expecting a state change.
    instance_ready_command = Executes this command on each instance provisioned by the autoscaler to ensure that it is ready for use. A failure results in the instance being removed.
  EOT
  type = object({
    fleeting_plugin_version        = optional(string, "1.0.0")
    connector_config_user          = optional(string, "ec2-user")
    key_pair_name                  = optional(string, "runner-worker-key")
    capacity_per_instance          = optional(number, 1)
    max_use_count                  = optional(number, 100)
    update_interval                = optional(string, "1m")
    update_interval_when_expecting = optional(string, "2s")
    instance_ready_command         = optional(string, "")
  })
  default = {}
}

variable "runner_worker_docker_autoscaler_instance" {
  description = <<-EOT
    ebs_optimized = Enable EBS optimization for the Runner Worker.
    http_tokens = Whether or not the metadata service requires session tokens.
    http_put_response_hop_limit = The desired HTTP PUT response hop limit for instance metadata requests. The larger the number, the further instance metadata requests can travel.
    monitoring = Enable detailed monitoring for the Runner Worker.
    private_address_only = Restrict Runner Worker to the use of a private IP address. If `runner_instance.use_private_address_only` is set to `true` (default),
    root_device_name = The name of the root volume for the Runner Worker.
    root_size = The size of the root volume for the Runner Worker.
    start_script = Cloud-init user data that will be passed to the Runner Worker. Should not be base64 encrypted.
    start_script_compression_algorithm = `gzip` compress the start script to mitigate the ~16 KB user data limit. Use `none` for Windows (EC2Launch does not support gzipped user data).
    volume_type = The type of volume to use for the Runner Worker. `gp2`, `gp3`, `io1` or `io2` are supported.
    volume_iops = Guaranteed IOPS for the volume. Only supported when using `gp3`, `io1` or `io2` as `volume_type`.
    volume_throughput = Throughput in MB/s for the volume. Only supported when using `gp3` as `volume_type`.
EOT

  type = object({
    ebs_optimized                      = optional(bool, true)
    http_tokens                        = optional(string, "required")
    http_put_response_hop_limit        = optional(number, 2)
    monitoring                         = optional(bool, false)
    private_address_only               = optional(bool, true)
    root_device_name                   = optional(string, "/dev/sda1")
    root_size                          = optional(number, 8)
    start_script                       = optional(string, "")
    start_script_compression_algorithm = optional(string, "gzip")
    volume_type                        = optional(string, "gp2")
    volume_throughput                  = optional(number, 125)
    volume_iops                        = optional(number, 3000)
  })
  default = {}

  validation {
    condition     = contains(["gzip", "none"], var.runner_worker_docker_autoscaler_instance.start_script_compression_algorithm)
    error_message = "The start_script_compression_algorithm supports `gzip` or `none`"
  }
}

variable "runner_worker_docker_autoscaler_asg" {
  description = <<-EOT
    enabled_metrics = List of metrics to collect.
    enable_mixed_instances_policy = Make use of autoscaling-group mixed_instances_policy capacities to leverage pools and spot instances.
    health_check_grace_period = Time (in seconds) after instance comes into service before checking health.
    health_check_type = Controls how health checking is done. Values are - EC2 and ELB.
    instance_refresh_min_healthy_percentage = The amount of capacity in the Auto Scaling group that must remain healthy during an instance refresh to allow the operation to continue, as a percentage of the desired capacity of the Auto Scaling group.
    instance_refresh_triggers = Set of additional property names that will trigger an Instance Refresh. A refresh will always be triggered by a change in any of launch_configuration, launch_template, or mixed_instances_policy.
    on_demand_base_capacity = Absolute minimum amount of desired capacity that must be fulfilled by on-demand instances.
    on_demand_percentage_above_base_capacity = Percentage split between on-demand and Spot instances above the base on-demand capacity.
    spot_allocation_strategy = How to allocate capacity across the Spot pools. 'lowest-price' to optimize cost, 'capacity-optimized' to reduce interruptions.
    spot_instance_pools = Number of Spot pools per availability zone to allocate capacity. EC2 Auto Scaling selects the cheapest Spot pools and evenly allocates Spot capacity across the number of Spot pools that you specify.
    subnet_ids = The list of subnet IDs to use for the Runner Worker when the fleet mode is enabled.
    default_instance_type = Default instance type for the launch template
    types = The type of instance to use for the Runner Worker. In case of fleet mode, multiple instance types are supported.
    upgrade_strategy = Auto deploy new instances when launch template changes. Can be either 'bluegreen', 'rolling' or 'off'.
    instance_requirements = Override the instance type in the Launch Template with instance types that satisfy the requirements.
  EOT
  type = object({
    enabled_metrics                          = optional(list(string), [])
    enable_mixed_instances_policy            = optional(bool, false)
    health_check_grace_period                = optional(number, 300)
    health_check_type                        = optional(string, "EC2")
    instance_refresh_min_healthy_percentage  = optional(number, 90)
    instance_refresh_triggers                = optional(list(string), [])
    on_demand_base_capacity                  = optional(number, 0)
    on_demand_percentage_above_base_capacity = optional(number, 100)
    spot_allocation_strategy                 = optional(string, "lowest-price")
    spot_instance_pools                      = optional(number, 2)
    subnet_ids                               = optional(list(string), [])
    default_instance_type                    = optional(string, "m5.large")
    types                                    = optional(list(string), [])
    upgrade_strategy                         = optional(string, "rolling")
    instance_requirements = optional(list(object({
      allowed_instance_types = optional(list(string), [])
      cpu_manufacturers      = optional(list(string), [])
      instance_generations   = optional(list(string), [])
      burstable_performance  = optional(string)
      memory_mib = optional(object({
        min = optional(number, null)
      max = optional(number, null) }), {})
      vcpu_count = optional(object({
        min = optional(number, null)
      max = optional(number, null) }), {})
    })), [])
  })
  default = {}

  validation {
    condition     = length(var.runner_worker_docker_autoscaler_asg.types) == 0 || length(var.runner_worker_docker_autoscaler_asg.instance_requirements) == 0
    error_message = "AWS does not allow setting both 'types' and 'instance_requirements' at the same time. Set only one."
  }
}

variable "runner_worker_docker_machine_role" {
  description = <<-EOT
    additional_tags = Map of tags that will be added to the Runner Worker.
    assume_role_policy_json = Assume role policy for the Runner Worker.
    policy_arns = List of ARNs of IAM policies to attach to the Runner Workers.
    profile_name    = Name of the IAM profile to attach to the Runner Workers.
  EOT
  type = object({
    additional_tags         = optional(map(string), {})
    assume_role_policy_json = optional(string, "")
    policy_arns             = optional(list(string), [])
    profile_name            = optional(string, "")
  })
  default = {}
}

variable "runner_worker_docker_autoscaler_role" {
  description = <<-EOT
    additional_tags = Map of tags that will be added to the Runner Worker.
    assume_role_policy_json = Assume role policy for the Runner Worker.
    policy_arns = List of ARNs of IAM policies to attach to the Runner Workers.
    profile_name    = Name of the IAM profile to attach to the Runner Workers.
  EOT
  type = object({
    additional_tags         = optional(map(string), {})
    assume_role_policy_json = optional(string, "")
    policy_arns             = optional(list(string), [])
    profile_name            = optional(string, "")
  })
  default = {}
}

variable "runner_worker_ingress_rules" {
  description = "Map of ingress rules for the Runner workers"
  type = map(object({
    from_port       = optional(number, null)
    to_port         = optional(number, null)
    protocol        = string
    description     = string
    cidr_block      = optional(string, null)
    ipv6_cidr_block = optional(string, null)
    prefix_list_id  = optional(string, null)
    security_group  = optional(string, null)
  }))
  default = {}

  validation {
    condition = alltrue([
      for rule in values(var.runner_worker_ingress_rules) :
      contains(["-1", "tcp", "udp", "icmp", "icmpv6"], rule.protocol)
    ])
    error_message = "Protocol must be '-1', 'tcp', 'udp', 'icmp', or 'icmpv6'."
  }

  validation {
    condition = alltrue([
      for rule in values(var.runner_worker_ingress_rules) :
      (rule.cidr_block != null) ||
      (rule.ipv6_cidr_block != null) ||
      (rule.prefix_list_id != null) ||
      (rule.security_group != null)
    ])
    error_message = "At least one destination must be specified."
  }
}

variable "runner_worker_egress_rules" {
  description = "Map of egress rules for the Runner workers"
  type = map(object({
    from_port       = optional(number, null)
    to_port         = optional(number, null)
    protocol        = string
    description     = string
    cidr_block      = optional(string, null)
    ipv6_cidr_block = optional(string, null)
    prefix_list_id  = optional(string, null)
    security_group  = optional(string, null)
  }))
  default = {}

  validation {
    condition = alltrue([
      for rule in values(var.runner_worker_egress_rules) :
      contains(["-1", "tcp", "udp", "icmp", "icmpv6"], rule.protocol)
    ])
    error_message = "Protocol must be '-1', 'tcp', 'udp', 'icmp', or 'icmpv6'."
  }

  validation {
    condition = alltrue([
      for rule in values(var.runner_worker_egress_rules) :
      (rule.cidr_block != null) ||
      (rule.ipv6_cidr_block != null) ||
      (rule.prefix_list_id != null) ||
      (rule.security_group != null)
    ])
    error_message = "At least one destination must be specified."
  }
}

variable "runner_worker_docker_machine_security_group_description" {
  description = "A description for the Runner Worker security group"
  type        = string
  default     = "A security group containing Runner Worker instances"
}

variable "runner_worker_docker_machine_ami_filter" {
  description = "List of maps used to create the AMI filter for the Runner Worker (docker-machine)."
  type        = map(list(string))

  default = {
    name = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }
}

variable "runner_worker_docker_machine_ami_owners" {
  description = "The list of owners used to select the AMI of the Runner Worker (docker-machine)."
  type        = list(string)

  default = ["099720109477"]
}

variable "runner_worker_docker_machine_ami_id" {
  description = "The ID of the AMI to use for the Runner Worker (docker-machine)."
  type        = string
  default     = ""
}

variable "runner_worker_docker_autoscaler_ami_filter" {
  description = "List of maps used to create the AMI filter for the Runner Worker (autoscaler)."
  type        = map(list(string))

  default = {
    name = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }
}

variable "runner_worker_docker_autoscaler_ami_owners" {
  description = "The list of owners used to select the AMI of the Runner Worker (autoscaler)."
  type        = list(string)

  default = ["099720109477"]
}

variable "runner_worker_docker_autoscaler_ami_id" {
  description = "The ID of the AMI to use for the Runner Worker (autoscaler)."
  type        = string
  default     = ""
}

variable "runner_worker_docker_machine_instance" {
  description = <<-EOT
    For detailed documentation check https://docs.gitlab.com/runner/configuration/advanced-configuration.html#the-runnersmachine-section

    docker_registry_mirror_url = The URL of the Docker registry mirror to use for the Runner Worker.
    destroy_after_max_builds = Destroy the instance after the maximum number of builds has been reached.
    ebs_optimized = Enable EBS optimization for the Runner Worker.
    idle_count = Number of idle Runner Worker instances (not working for the Docker Runner Worker) (IdleCount).
    idle_time = Idle time of the Runner Worker before they are destroyed (not working for the Docker Runner Worker) (IdleTime).
    max_growth_rate = The maximum number of machines that can be added to the runner in parallel.
    monitoring = Enable detailed monitoring for the Runner Worker.
    name_prefix = Set the name prefix and override the `Name` tag for the Runner Worker.
    private_address_only = Restrict Runner Worker to the use of a private IP address. If `runner_instance.use_private_address_only` is set to `true` (default), `runner_worker_docker_machine_instance.private_address_only` will also apply for the Runner.
    root_device_name = The name of the root volume for the Runner Worker.
    root_size = The size of the root volume for the Runner Worker.
    start_script = Cloud-init user data that will be passed to the Runner Worker. Should not be base64 encrypted.
    subnet_ids = The list of subnet IDs to use for the Runner Worker when the fleet mode is enabled.
    types = The type of instance to use for the Runner Worker. In case of fleet mode, multiple instance types are supported.
    volume_type = The type of volume to use for the Runner Worker. `gp2`, `gp3`, `io1` or `io2` are supported.
    volume_throughput = Throughput in MB/s for the volume. Only supported when using `gp3` as `volume_type`.
    volume_iops = Guaranteed IOPS for the volume. Only supported when using `gp3`, `io1` or `io2` as `volume_type`. Works for fleeting only. See `runner_worker_docker_machine_fleet`.
  EOT
  type = object({
    destroy_after_max_builds   = optional(number, 0)
    docker_registry_mirror_url = optional(string, "")
    ebs_optimized              = optional(bool, true)
    idle_count                 = optional(number, 0)
    idle_time                  = optional(number, 600)
    max_growth_rate            = optional(number, 0)
    monitoring                 = optional(bool, false)
    name_prefix                = optional(string, "")
    private_address_only       = optional(bool, true)
    root_device_name           = optional(string, "/dev/sda1")
    root_size                  = optional(number, 8)
    start_script               = optional(string, "")
    subnet_ids                 = optional(list(string), [])
    types                      = optional(list(string), ["m5.large"])
    volume_type                = optional(string, "gp2")
    volume_throughput          = optional(number, 125)
    volume_iops                = optional(number, 3000)
  })
  default = {
  }

  validation {
    condition     = length(var.runner_worker_docker_machine_instance.name_prefix) <= 28
    error_message = "Maximum length for docker+machine executor name is 28 characters!"
  }

  validation {
    condition     = var.runner_worker_docker_machine_instance.name_prefix == "" || can(regex("^[a-zA-Z0-9\\.-]+$", var.runner_worker_docker_machine_instance.name_prefix))
    error_message = "Valid characters for the docker+machine executor name are: [a-zA-Z0-9\\.-]."
  }

  validation {
    condition     = contains(["gp2", "gp3", "io1", "io2"], var.runner_worker_docker_machine_instance.volume_type)
    error_message = "Supported volume types: gp2, gp3, io1 and io2"
  }
}

variable "runner_worker_docker_machine_instance_spot" {
  description = <<-EOT
    enable = Enable spot instances for the Runner Worker.
    max_price = The maximum price willing to pay. By default the price is limited by the current on demand price for the instance type chosen.
  EOT
  type = object({
    enable    = optional(bool, true)
    max_price = optional(string, "on-demand-price")
  })
  default = {}
}

variable "runner_worker_docker_machine_ec2_options" {
  description = "List of additional options for the docker+machine config. Each element of this list must be a key=value pair. E.g. '[\"amazonec2-zone=a\"]'"
  type        = list(string)
  default     = []
}

variable "runner_worker_docker_machine_ec2_metadata_options" {
  description = "Enable the Runner Worker metadata service. Requires you use CKI maintained docker machines."
  type = object({
    http_tokens                 = string
    http_put_response_hop_limit = number
  })
  default = {
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }
}

variable "runner_worker_docker_machine_autoscaling_options" {
  description = "Set autoscaling parameters based on periods, see https://docs.gitlab.com/runner/configuration/advanced-configuration.html#the-runnersmachine-section"
  type = list(object({
    periods           = list(string)
    idle_count        = optional(number)
    idle_scale_factor = optional(number)
    idle_count_min    = optional(number)
    idle_time         = optional(number)
    timezone          = optional(string, "UTC")
  }))
  default = []
}

variable "runner_worker_docker_autoscaler_autoscaling_options" {
  description = "Set autoscaling parameters based on periods, see https://docs.gitlab.com/runner/configuration/advanced-configuration.html#the-runnersautoscalerpolicy-sections"
  type = list(object({
    periods            = list(string)
    timezone           = optional(string, "UTC")
    idle_count         = optional(number)
    idle_time          = optional(string)
    scale_factor       = optional(number)
    scale_factor_limit = optional(number, 0)
    preemptive_mode    = optional(bool)
  }))
  default = []
}

variable "debug" {
  description = <<-EOT
    trace_runner_user_data: Enable bash trace for the user data script on the Agent. Be aware this could log sensitive data such as you GitLab runner token.
    write_runner_config_to_file: When enabled, outputs the rendered config.toml file in the root module. Note that enabling this can
                                 potentially expose sensitive information.
    write_runner_user_data_to_file: When enabled, outputs the rendered userdata.sh file in the root module. Note that enabling this
                                    can potentially expose sensitive information.
  EOT
  type = object({
    trace_runner_user_data         = optional(bool, false)
    write_runner_config_to_file    = optional(bool, false)
    write_runner_user_data_to_file = optional(bool, false)
  })
  default = {}
}

terraform {
  required_version = ">= 1.3"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0.0"
    }
    local = {
      source  = "hashicorp/local"
      version = ">= 2.4.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = ">= 3"
    }
  }
}