```hcl
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
  count = length(var.runner_ami_id) > 0? 0 : 1

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
  count = var.runner_worker.type == "docker+machine" && length(var.runner_worker_docker_machine_ami_id) == 0? 1 : 0

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
  count = var.runner_worker.type == "docker-autoscaler" && length(var.runner_worker_docker_autoscaler_ami_id) == 0? 1 : 0

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
  count = var.runner_worker.type == "docker-autoscaler"? 1 : 0

  name          = "${local.name_runner_agent_instance}-worker-launch-template"
  user_data     = var.runner_worker_docker_autoscaler_instance.start_script_compression_algorithm == "gzip"? base64gzip(var.runner_worker_docker_autoscaler_instance.start_script) : base64encode(var.runner_worker_docker_autoscaler_instance.start_script)
  image_id      = length(var.runner_worker_docker_autoscaler_ami_id) > 0? var.runner_worker_docker_autoscaler_ami_id : data.aws_ami.docker_autoscaler_by_filter[0].id
  instance_type = length(var.runner_worker_docker_autoscaler_asg.types) > 0? var.runner_worker_docker_autoscaler_asg.types[0] : var.runner_worker_docker_autoscaler_asg.default_instance_type
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
    associate_public_ip_address =!var.runner_worker_docker_autoscaler_instance.private_address_only
  }

  block_device_mappings {
    device_name = var.runner_worker_docker_autoscaler_instance.root_device_name

    ebs {
      volume_size = var.runner_worker_docker_autoscaler_instance.root_size
      volume_type = var.runner_worker_docker_autoscaler_instance.volume_type
      iops        = contains(["gp3", "io1", "io2"], var.runner_worker_docker_autoscaler_instance.volume_type)? var.runner_worker_docker_autoscaler_instance.volume_iops : null
      throughput  = var.runner_worker_docker_autoscaler_instance.volume_type == "gp3"? var.runner_worker_docker_autoscaler_instance.volume_throughput : null
      encrypted   = true
      kms_key_id  = local.kms_key_arn!= ""? local.kms_key_arn : null
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
  count = var.runner_worker.type == "docker-autoscaler"? 1 : 0

  name                  = "${local.name_runner_agent_instance}-asg"
  capacity_rebalance    = false
  protect_from_scale_in = true
  suspended_processes   = ["AZRebalance"]

  dynamic "launch_template" {
    for_each = var.runner_worker_docker_autoscaler_asg.enable_mixed_instances_policy? [] : [1]
    content {
      id      = aws_launch_template.this[0].id
      version = aws_launch_template.this[0].latest_version
    }
  }

  dynamic "mixed_instances_policy" {
    for_each = var.runner_worker_docker_autoscaler_asg.enable_mixed_instances_policy? [1] : []

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
    for_each = var.runner_worker_docker_autoscaler_asg.upgrade_strategy == "rolling"? [1] : []
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
  desired_capacity          = 0 # managed by the fleeting plugin
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
  count = var.runner_worker.type == "docker-autoscaler"? 1 : 0
  name  = "${local.name_iam_objects}-docker-autoscaler"
  role  = aws_iam_role.docker_autoscaler[0].name
  tags  = local.tags
}

resource "tls_private_key" "autoscaler" {
  count = var.runner_worker.type == "docker-autoscaler"? 1 : 0

  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "autoscaler" {
  count = var.runner_worker.type == "docker-autoscaler"? 1 : 0

  key_name   = "${var.environment}-${var.runner_worker_docker_autoscaler.key_pair_name}"
  public_key = tls_private_key.autoscaler[0].public_key_openssh

  tags = local.tags
}

resource "aws_iam_role" "docker_autoscaler" {
  count                = var.runner_worker.type == "docker-autoscaler"? 1 : 0
  name                 = "${local.name_iam_objects}-docker-autoscaler"
  assume_role_policy   = length(var.runner_worker_docker_autoscaler_role.assume_role_policy_json) > 0? var.runner_worker_docker_autoscaler_role.assume_role_policy_json : templatefile("${path.module}/policies/instance-role-trust-policy.json", {})
  permissions_boundary = var.iam_permissions_boundary == ""? null : "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:policy/${var.iam_permissions_boundary}"

  tags = merge(local.tags, var.runner_worker_docker_autoscaler_role.additional_tags)
}

resource "aws_iam_policy" "instance_docker_autoscaler_policy" {
  count = var.runner_worker.type == "docker-autoscaler" && var.runner_role.create_role_profile? 1 : 0

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
  count = var.runner_worker.type == "docker-autoscaler" && var.runner_role.create_role_profile? 1 : 0

  role       = aws_iam_role.instance[0].name
  policy_arn = aws_iam_policy.instance_docker_autoscaler_policy[0].arn
}

resource "aws_iam_role_policy_attachment" "docker_autoscaler_user_defined_policies" {
  count = var.runner_worker.type == "docker-autoscaler"? length(var.runner_worker_docker_autoscaler_role.policy_arns) : 0

  role       = aws_iam_role.docker_autoscaler[0].name
  policy_arn = var.runner_worker_docker_autoscaler_role.policy_arns[count.index]
}

resource "aws_iam_role_policy_attachment" "docker_autoscaler_session_manager_aws_managed" {
  count = (var.runner_worker.type == "docker-autoscaler" && var.runner_worker.ssm_access)? 1 : 0

  role       = aws_iam_role.docker_autoscaler[0].name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_security_group" "docker_autoscaler" {
  count       = var.runner_worker.type == "docker-autoscaler"? 1 : 0
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
  for_each = var.runner_worker.type == "docker-autoscaler"? var.runner_worker_ingress_rules : {}

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
  count = var.runner_worker.type == "docker-autoscaler"? 1 : 0

  security_group_id            = aws_security_group.docker_autoscaler[0].id
  from_port                    = -1
  to_port                      = -1
  ip_protocol                  = "-1"
  description                  = "Allow ALL Ingress traffic between Runner Manager and Docker-autoscaler workers security group"
  referenced_security_group_id = aws_security_group.runner.id

  tags = local.tags
}

resource "aws_vpc_security_group_egress_rule" "docker_autoscaler_egress" {
  for_each = var.runner_worker.type == "docker-autoscaler"? var.runner_worker_egress_rules : {}

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
      docker_machine_name    = format("%s-%s", local.runner_tags_merged["Name"], "%s") # %s is always needed
      runners_instance_types = var.runner_worker_docker_machine_instance.types
      aws_region             = data.aws_region.current.region
      runners_aws_zone       = data.aws_availability_zone.runners.name_suffix
      runners_userdata       = var.runner_worker_docker_machine_instance.start_script

      runners_vpc_id           = var.vpc_id
      runners_subnet_id        = var.subnet_id
      runners_subnet_ids       = length(var.runner_worker_docker_machine_instance.subnet_ids) > 0? var.runner_worker_docker_machine_instance.subnet_ids : [var.subnet_id]
      runners_instance_profile = var.runner_worker.type == "docker+machine"? aws_iam_instance_profile.docker_machine[0].name : ""

      runners_use_private_address_only = var.runner_worker_docker_machine_instance.private_address_only
      runners_use_private_address      =!var.runner_worker_docker_machine_instance.private_address_only
      runners_request_spot_instance    = var.runner_worker_docker_machine_instance_spot.enable
      runners_spot_price_bid           = var.runner_worker_docker_machine_instance_spot.max_price == "on-demand-price" || var.runner_worker_docker_machine_instance_spot.max_price == null? "" : var.runner_worker_docker_machine_instance_spot.max_price
      runners_security_group_name      = var.runner_worker.type == "docker+machine"? aws_security_group.docker_machine[0].name : ""

      runners_tags                      = replace(replace(local.runner_tags_string, ",,", ","), "/,$/", "")
      runners_ebs_optimized             = var.runner_worker_docker_machine_instance.ebs_optimized
      runners_monitoring                = var.runner_worker_docker_machine_instance.monitoring
      runners_iam_instance_profile_name = var.runner_worker_docker_machine_role.profile_name
      runners_root_size                 = var.runner_worker_docker_machine_instance.root_size
      runners_volume_type               = var.runner_worker_docker_machine_instance.volume_type
      runners_ami                       = var.runner_worker.type == "docker+machine"? (length(var.runner_worker_docker_machine_ami_id) > 0? var.runner_worker_docker_machine_ami_id : data.aws_ami.docker_machine_by_filter[0].id) : ""
      use_fleet                         = var.runner_worker_docker_machine_fleet.enable
      launch_template                   = var.runner_worker_docker_machine_fleet.enable == true? aws_launch_template.fleet_gitlab_runner[0].name : ""
      docker_machine_options            = length(local.docker_machine_options_string) == 1? "" : local.docker_machine_options_string
      runners_max_growth_rate           = var.runner_worker_docker_machine_instance.max_growth_rate
      runners_volume_kms_key            = local.kms_key_arn
  })
}

resource "aws_iam_instance_profile" "docker_machine" {
  count = var.runner_worker.type == "docker+machine"? 1 : 0
  name  = "${local.name_iam_objects}-docker-machine"
  role  = aws_iam_role.docker_machine[0].name
  tags  = local.tags
}

resource "aws_key_pair" "fleet" {
  count = var.runner_worker_docker_machine_fleet.enable == true && var.runner_worker.type == "docker+machine"? 1 : 0

  key_name   = "${var.environment}-${var.runner_worker_docker_machine_fleet.key_pair_name}"
  public_key = tls_private_key.fleet[0].public_key_openssh

  tags = local.tags
}

resource "tls_private_key" "fleet" {
  count = var.runner_worker_docker_machine_fleet.enable == true && var.runner_worker.type == "docker+machine"? 1 : 0

  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_launch_template" "fleet_gitlab_runner" {
  count       = var.runner_worker_docker_machine_fleet.enable == true && var.runner_worker.type == "docker+machine"? 1 : 0
  name_prefix = "${local.name_runner_agent_instance}-worker-"

  key_name               = aws_key_pair.fleet[0].key_name
  image_id               = length(var.runner_worker_docker_machine_ami_id) > 0? var.runner_worker_docker_machine_ami_id : data.aws_ami.docker_machine_by_filter[0].id
  user_data              = base64gzip(var.runner_worker_docker_machine_instance.start_script)
  instance_type          = var.runner_worker_docker_machine_instance.types[0] # it will be override by the fleet
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
      iops        = contains(["gp3", "io1", "io2"], var.runner_worker_docker_machine_instance.volume_type)? var.runner_worker_docker_machine_instance.volume_iops : null
      throughput  = var.runner_worker_docker_machine_instance.volume_type == "gp3"? var.runner_worker_docker_machine_instance.volume_throughput : null
      encrypted   = true
      kms_key_id  = local.kms_key_arn!= ""? local.kms_key_arn : null
    }
  }

  iam_instance_profile {
    name = aws_iam_instance_profile.docker_machine[0].name
  }

  network_interfaces {
    security_groups             = [aws_security_group.docker_machine[0].id]
    associate_public_ip_address =!var.runner_worker_docker_machine_instance.private_address_only
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
  count                = var.runner_worker.type == "docker+machine"? 1 : 0
  name                 = "${local.name_iam_objects}-docker-machine"
  assume_role_policy   = length(var.runner_worker_docker_machine_role.assume_role_policy_json) > 0? var.runner_worker_docker_machine_role.assume_role_policy_json : templatefile("${path.module}/policies/instance-role-trust-policy.json", {})
  permissions_boundary = var.iam_permissions_boundary == ""? null : "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:policy/${var.iam_permissions_boundary}"

  tags = merge(local.tags, var.runner_worker_docker_machine_role.additional_tags)
}

resource "aws_iam_policy" "instance_docker_machine_policy" {
  count = var.runner_worker.type == "docker+machine" && var.runner_role.create_role_profile? 1 : 0

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
  count = var.runner_worker.type == "docker+machine" && var.runner_role.create_role_profile? 1 : 0

  role       = aws_iam_role.instance[0].name
  policy_arn = aws_iam_policy.instance_docker_machine_policy[0].arn
}

resource "aws_iam_role_policy_attachment" "docker_machine_user_defined_policies" {
  count = var.runner_worker.type == "docker+machine"? length(var.runner_worker_docker_machine_role.policy_arns) : 0

  role       = aws_iam_role.docker_machine[0].name
  policy_arn = var.runner_worker_docker_machine_role.policy_arns[count.index]
}

resource "aws_iam_role_policy_attachment" "docker_machine_session_manager_aws_managed" {
  count = (var.runner_worker.type == "docker+machine" && var.runner_worker.ssm_access)? 1 : 0

  role       = aws_iam_role.docker_machine[0].name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

locals {
  security_groups_ping = var.runner_networking.allow_incoming_ping && length(var.runner_networking.allow_incoming_ping_security_group_ids) > 0? concat(var.runner_networking.allow_incoming_ping_security_group_ids, [aws_security_group.runner.id]) : []
}

resource "aws_security_group" "docker_machine" {
  count = var.runner_worker.type == "docker+machine"? 1 : 0

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
  for_each = var.runner_worker.type == "docker+machine"? var.runner_worker_ingress_rules : {}

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
  count = var.runner_worker.type == "docker+machine"? 1 : 0

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
  count = var.runner_worker.type == "docker+machine"? 1 : 0

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
  count = var.runner_worker.type == "docker+machine"? length(local.security_groups_ping) : 0

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
  count = var.runner_worker.type == "docker+machine"? 1 : 0

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
  count = var.runner_worker.type == "docker+machine"? 1 : 0

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
  count = (var.runner_worker.type == "docker+machine" && var.runner_networking.allow_incoming_ping)? 1 : 0

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
  count = var.enable_managed_kms_key? 1 : 0

  description             = "GitLab Runner module managed key - ${var.environment}"
  deletion_window_in_days = var.kms_managed_deletion_rotation_window_in_days > 0? var.kms_managed_deletion_rotation_window_in_days : null
  enable_key_rotation     = var.kms_managed_deletion_rotation_window_in_days > 0? true : false
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
  count         = var.enable_managed_kms_key && var.kms_managed_alias_name!= ""? 1 : 0
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

  runners_docker_registry_mirror_option = var.runner_worker_docker_machine_instance.docker_registry_mirror_url == ""? [] : ["engine-registry-mirror=${var.runner_worker_docker_machine_instance.docker_registry_mirror_url}"]

  runners_docker_options_toml = templatefile("${path.module}/template/runners_docker_options.tftpl", {
    options = merge({
      for key, value in var.runner_worker_docker_options : key => value if value!= null && key!= "volumes" && key!= "pull_policies"
      }, {
      pull_policy = var.runner_worker_docker_options.pull_policies
      volumes     = local.runners_volumes
    })
    }
  )

  runners_max_builds_string = var.runner_worker_docker_machine_instance.destroy_after_max_builds == 0? "" : format("MaxBuilds = %d", var.runner_worker_docker_machine_instance.destroy_after_max_builds)

  secure_parameter_store_runner_token_key  = "${var.environment}-${var.runner_gitlab_token_secure_parameter_store}"
  secure_parameter_store_runner_sentry_dsn = "${var.environment}-${var.runner_sentry_secure_parameter_store_name}"

  name_runner_agent_instance = var.runner_instance.name_prefix == null? local.tags["Name"] : var.runner_instance.name_prefix
  name_sg                    = var.security_group_prefix == ""? local.tags["Name"] : var.security_group_prefix
  name_iam_objects           = var.iam_object_prefix == ""? local.tags["Name"] : var.iam_object_prefix

  runners_volumes = concat(var.runner_worker_docker_options.volumes, var.runner_worker_docker_add_dind_volumes? ["/certs/client", "/builds", "/var/run/docker.sock:/var/run/docker.sock"] : [])

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

  kms_key_arn = local.provided_kms_key == "" && var.enable_managed_kms_key? aws_kms_key.default