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


#
# This file is responsible for creating the resources needed to run the docker autoscaler plugin from GitLab. It replaces the
# outdated docker+machine driver. The docker+machine driver is a legacy driver that is no longer maintained by GitLab.
#

####################################
###### Launch template Workers #####
####################################
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

  # as per user decision. The module default is "required" for better security.
  # tfsec:ignore:aws-ec2-enforce-launch-config-http-token-imds
  metadata_options {
    # the module enables IMDSv2 by default, but lets the user decide
    # kics-scan ignore-line
    http_tokens                 = var.runner_worker_docker_autoscaler_instance.http_tokens
    http_put_response_hop_limit = var.runner_worker_docker_autoscaler_instance.http_put_response_hop_limit
    instance_metadata_tags      = "enabled"
  }

  lifecycle {
    create_before_destroy = true
  }
}

#########################################
# Autoscaling group with launch template
#########################################
# false positive, tags are created with "dynamic" block
# kics-scan ignore-line
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
    # do not change desired_capacity as this is controlled at runtime by the runner autoscaler
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
  # see https://gitlab.com/gitlab-org/fleeting/plugins/aws#recommended-iam-policy for needed policies
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


# kics-scan ignore-block
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

# Ingress rules
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

# Egress rules
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
      docker_machine_name    = format("%s-%s", local.runner_tags_merged["Name"], "%s") # %s is always needed
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
  # checkov:skip=CKV_AWS_88:User can decide to add a public IP.
  # checkov:skip=CKV_AWS_79:User can decide to enable Metadata service V2. V2 is the default.
  # checkov:skip=CKV_AWS_341:Hop limit is user-defined and set to 2 by default as the workload might run in a Docker container.
  count       = var.runner_worker_docker_machine_fleet.enable == true && var.runner_worker.type == "docker+machine" ? 1 : 0
  name_prefix = "${local.name_runner_agent_instance}-worker-"

  key_name               = aws_key_pair.fleet[0].key_name
  image_id               = length(var.runner_worker_docker_machine_ami_id) > 0 ? var.runner_worker_docker_machine_ami_id : data.aws_ami.docker_machine_by_filter[0].id
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
  # tag_specifications for spot-instances-request do not work. Instance creation fails.

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


################################################################################
### docker machine instance policy
################################################################################
resource "aws_iam_role" "docker_machine" {
  count                = var.runner_worker.type == "docker+machine" ? 1 : 0
  name                 = "${local.name_iam_objects}-docker-machine"
  assume_role_policy   = length(var.runner_worker_docker_machine_role.assume_role_policy_json) > 0 ? var.runner_worker_docker_machine_role.assume_role_policy_json : templatefile("${path.module}/policies/instance-role-trust-policy.json", {})
  permissions_boundary = var.iam_permissions_boundary == "" ? null : "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:policy/${var.iam_permissions_boundary}"

  tags = merge(local.tags, var.runner_worker_docker_machine_role.additional_tags)
}

################################################################################
### Policies for runner agent instance to create docker machines via spot req.
###
### iam:PassRole To pass the role from the agent to the docker machine runners
################################################################################
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

################################################################################
### Add user defined policies
################################################################################
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


# Combine runner security group id and additional security group IDs
locals {
  # Only include runner security group id and additional if ping is enabled
  security_groups_ping = var.runner_networking.allow_incoming_ping && length(var.runner_networking.allow_incoming_ping_security_group_ids) > 0 ? concat(var.runner_networking.allow_incoming_ping_security_group_ids, [aws_security_group.runner.id]) : []
}

# kics-scan ignore-block
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

########################################
## Runner agent to docker-machine     ##
########################################

# Allow docker-machine traffic from gitlab-runner agent instances to docker-machine instances
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

# Allow SSH traffic from gitlab-runner agent instances and security group IDs to docker-machine instances
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

# Allow ICMP traffic from gitlab-runner agent instances and security group IDs to docker-machine instances
resource "aws_vpc_security_group_ingress_rule" "docker_machine_ping_runner" {
  # checkov:skip=CKV_AWS_277:False positive. ICMP traffic has no ports.
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

########################################
## Docker-machine instances to self   ##
########################################

# Allow docker-machine traffic from docker-machine instances to docker-machine instances on port 2376
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

# Allow SSH traffic from docker-machine instances to docker-machine instances on port 22
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

# Allow ICMP traffic from docker-machine instances to docker-machine instances
resource "aws_vpc_security_group_ingress_rule" "docker_machine_ping_self" {
  # checkov:skip=CKV_AWS_277:False positive. ICMP traffic has no ports.
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
  # Manage certificates
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
    # If either (or both) _certificate variables are specified
    length(var.runner_gitlab.certificate) + length(var.runner_gitlab.ca_certificate) > 0
    ? join("\n", [
      local.pre_install_gitlab_certificate,
      local.pre_install_ca_certificate,
      local.pre_install_certificates_end
    ])
    : ""
  )

  # Determine IAM role for runner instance
  aws_iam_role_instance_name = coalesce(
    var.runner_role.role_profile_name,
    "${local.name_iam_objects}-instance"
  )
  aws_iam_role_instance_arn = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/${local.aws_iam_role_instance_name}"

  # Convert list to a string separated and prepend by a comma
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

  # Ensure max builds is optional
  runners_max_builds_string = var.runner_worker_docker_machine_instance.destroy_after_max_builds == 0 ? "" : format("MaxBuilds = %d", var.runner_worker_docker_machine_instance.destroy_after_max_builds)

  # Define key for runner token for SSM
  secure_parameter_store_runner_token_key  = "${var.environment}-${var.runner_gitlab_token_secure_parameter_store}"
  secure_parameter_store_runner_sentry_dsn = "${var.environment}-${var.runner_sentry_secure_parameter_store_name}"

  # Custom names for runner agent instance, security groups, and IAM objects
  name_runner_agent_instance = var.runner_instance.name_prefix == null ? local.tags["Name"] : var.runner_instance.name_prefix
  name_sg                    = var.security_group_prefix == "" ? local.tags["Name"] : var.security_group_prefix
  name_iam_objects           = var.iam_object_prefix == "" ? local.tags["Name"] : var.iam_object_prefix

  runners_volumes = concat(var.runner_worker_docker_options.volumes, var.runner_worker_docker_add_dind_volumes ? ["/certs/client", "/builds", "/var/run/docker.sock:/var/run/docker.sock"] : [])

  runners_docker_services = templatefile("${path.module}/template/runners_docker_services.tftpl", {
    runners_docker_services = var.runner_worker_docker_services
    }
  )

  /* determines if the docker machine executable adds the Name tag automatically (versions >= 0.16.2) */
  # make sure to skip pre-release stuff in the semver by ignoring everything after "-"
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

# ignored as decided by the user
# tfsec:ignore:aws-cloudwatch-log-group-customer-key
resource "aws_cloudwatch_log_group" "environment" {
  count = var.runner_cloudwatch.enable ? 1 : 0
  name  = var.runner_cloudwatch.log_group_name != null ? var.runner_cloudwatch.log_group_name : var.environment
  # ignores a false positive: retention_in_days not set
  # kics-scan ignore-line
  retention_in_days = var.runner_cloudwatch.retention_days
  tags              = local.tags

  # ignored as decided by the user
  # checkov:skip=CKV_AWS_158:Encryption can be enabled by user
  kms_key_id = local.kms_key_arn
}


# Parameter value is managed by the user-data script of the gitlab runner instance
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

  # "16.0.3" -> ["16", "0", "3"]
  runner_version_split = split(".", var.runner_gitlab.runner_version)
  # ["16", "0", "3"] -> 16
  runner_version_major = parseint(local.runner_version_split[0], 10)
  # ["16", "0", "3"] -> 0
  runner_version_minor = parseint(local.runner_version_split[1], 10)
  # the `gitlab-runner fleeting install` command was introduced in 16.11
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
        # Convert key from snake_case to PascalCase which is the casing for this section.
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
        # Convert key from snake_case to PascalCase which is the casing for this section.
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

# ignores: Autoscaling Groups Supply Tags --> we use a "dynamic" block to create the tags
# ignores: Auto Scaling Group With No Associated ELB --> that's simply not true, as the EC2 instance contacts GitLab. So no ELB needed here.
# kics-scan ignore-line
resource "aws_autoscaling_group" "gitlab_runner_instance" {
  # TODO Please explain how `agent_enable_asg_recreation` works
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
  # checkov:skip=CKV_AWS_341:Hop limit > 1 needed here in case of Docker builds. Otherwise the token is invalid within Docker.
  # checkov:skip=CKV_AWS_88:User can decide to add a public IP.
  # checkov:skip=CKV_AWS_79:User can decide to enable Metadata service V2. V2 is the default.
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

  # otherwise the agent running on the EC2 instance tries to create the log group
  depends_on = [aws_cloudwatch_log_group.environment]
}

################################################################################
### Create cache bucket
################################################################################
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

################################################################################
### Trust policy
################################################################################
resource "aws_iam_instance_profile" "instance" {
  count = var.runner_role.create_role_profile ? 1 : 0

  name = local.aws_iam_role_instance_name
  role = local.aws_iam_role_instance_name

  tags = local.tags
}

# "AWS EIP not attached to any instance": we attach it via user-data script
# kics-scan ignore-block
resource "aws_eip" "gitlab_runner" {
  # checkov:skip=CKV2_AWS_19:We can't use NAT gateway here as we are contacted from the outside.
  # checkov:skip=CKV2_AWS_20:We can't use NAT gateway here as we are contacted from the outside.
  count = var.runner_instance.use_eip ? 1 : 0

  tags = local.tags
}

# We wait for 5 minutes until we set an EC2 instance to status `InService` so it has time to provision itself and it's configured capacity.
resource "aws_autoscaling_lifecycle_hook" "wait_for_gitlab_runner" {
  name                   = "${var.environment}-wait-for-gitlab-runner-up"
  autoscaling_group_name = aws_autoscaling_group.gitlab_runner_instance.name
  default_result         = "CONTINUE"
  heartbeat_timeout      = 300
  lifecycle_transition   = "autoscaling:EC2_INSTANCE_LAUNCHING"
}

################################################################################
### Lambda function triggered as soon as an agent is terminated.
################################################################################
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
  description = "Name of the role used for the