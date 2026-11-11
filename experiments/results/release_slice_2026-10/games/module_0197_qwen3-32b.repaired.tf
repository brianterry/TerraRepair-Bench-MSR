data "aws_partition" "current" {}

locals {
  create = var.create && var.putin_khuylo

  is_t_instance_type = replace(var.instance_type, "/^t(2|3|3a|4g){1}\\..*$/", "1") == "1" ? true : false

  ami = try(coalesce(var.ami, try(nonsensitive(data.aws_ssm_parameter.this.value), null)), null)

  instance_tags = merge(
    var.tags,
    var.instance_tags,
    var.name != "" ? { "Name" = var.name } : {}
  )

  instance_id = try(
    aws_instance.this[0].id,
    aws_instance.ignore_ami[0].id,
    aws_spot_instance_request.this[0].spot_instance_id,
    null,
  )

  instance_availability_zone = try(
    aws_instance.this[0].availability_zone,
    aws_instance.ignore_ami[0].availability_zone,
    aws_spot_instance_request.this[0].availability_zone,
    null,
  )
}

data "aws_ssm_parameter" "this" {
  region = var.region

  name = var.ami_ssm_parameter
}

################################################################################
# Instance
################################################################################

resource "aws_instance" "this" {
  count = local.create && !var.ignore_ami_changes && !var.create_spot_instance ? 1 : 0

  region = var.region

  ami                         = local.ami
  associate_public_ip_address = var.associate_public_ip_address
  availability_zone           = var.availability_zone

  dynamic "capacity_reservation_specification" {
    for_each = var.capacity_reservation_specification != null ? [var.capacity_reservation_specification] : []

    content {
      capacity_reservation_preference = capacity_reservation_specification.value.capacity_reservation_preference

      dynamic "capacity_reservation_target" {
        for_each = capacity_reservation_specification.value.capacity_reservation_target != null ? [capacity_reservation_specification.value.capacity_reservation_target] : []

        content {
          capacity_reservation_id                 = capacity_reservation_target.value.capacity_reservation_id
          capacity_reservation_resource_group_arn = capacity_reservation_target.value.capacity_reservation_resource_group_arn
        }
      }
    }
  }

  dynamic "cpu_options" {
    for_each = var.cpu_options != null ? [var.cpu_options] : []

    content {
      amd_sev_snp      = cpu_options.value.amd_sev_snp
      core_count       = cpu_options.value.core_count
      threads_per_core = cpu_options.value.threads_per_core
    }
  }

  credit_specification {
    cpu_credits = local.is_t_instance_type ? var.cpu_credits : null
  }

  disable_api_stop        = var.disable_api_stop
  disable_api_termination = var.disable_api_termination

  # `ebs_block_device` managed by separate resource

  ebs_optimized = var.ebs_optimized

  enclave_options {
    enabled = var.enclave_options_enabled
  }

  enable_primary_ipv6 = var.enable_primary_ipv6

  dynamic "ephemeral_block_device" {
    for_each = var.ephemeral_block_device != null ? var.ephemeral_block_device : {}

    content {
      device_name  = ephemeral_block_device.value.device_name
      no_device    = ephemeral_block_device.value.no_device
      virtual_name = ephemeral_block_device.value.virtual_name
    }
  }

  get_password_data                    = var.get_password_data
  hibernation                          = var.hibernation
  host_id                              = var.host_id
  host_resource_group_arn              = var.host_resource_group_arn
  iam_instance_profile                 = var.create_iam_instance_profile ? aws_iam_instance_profile.this[0].name : var.iam_instance_profile
  instance_initiated_shutdown_behavior = var.instance_initiated_shutdown_behavior

  dynamic "instance_market_options" {
    for_each = var.instance_market_options != null ? [var.instance_market_options] : []

    content {
      market_type = instance_market_options.value.market_type

      dynamic "spot_options" {
        for_each = instance_market_options.value.spot_options != null ? [instance_market_options.value.spot_options] : []

        content {
          instance_interruption_behavior = spot_options.value.instance_interruption_behavior
          max_price                      = spot_options.value.max_price
          spot_instance_type             = spot_options.value.spot_instance_type
          valid_until                    = spot_options.value.valid_until
        }
      }
    }
  }

  instance_type      = var.instance_type
  ipv6_address_count = var.ipv6_address_count
  ipv6_addresses     = var.ipv6_addresses
  key_name           = var.key_name

  dynamic "launch_template" {
    for_each = var.launch_template != null ? [var.launch_template] : []

    content {
      id      = launch_template.value.id
      name    = launch_template.value.name
      version = launch_template.value.version
    }
  }

  dynamic "maintenance_options" {
    for_each = var.maintenance_options != null ? [var.maintenance_options] : []

    content {
      auto_recovery = maintenance_options.value.auto_recovery
    }
  }

  dynamic "metadata_options" {
    for_each = var.metadata_options != null ? [var.metadata_options] : []

    content {
      http_endpoint               = metadata_options.value.http_endpoint
      http_protocol_ipv6          = metadata_options.value.http_protocol_ipv6
      http_put_response_hop_limit = metadata_options.value.http_put_response_hop_limit
      http_tokens                 = metadata_options.value.http_tokens
      instance_metadata_tags      = metadata_options.value.instance_metadata_tags
    }
  }

  monitoring = var.monitoring

  dynamic "network_interface" {
    for_each = var.network_interface != null ? var.network_interface : {}

    content {
      delete_on_termination = network_interface.value.delete_on_termination
      device_index          = coalesce(network_interface.value.device_index, network_interface.key)
      network_card_index    = network_interface.value.network_card_index
      network_interface_id  = network_interface.value.network_interface_id

    }
  }

  placement_group            = var.placement_group
  placement_partition_number = var.placement_partition_number

  dynamic "private_dns_name_options" {
    for_each = var.private_dns_name_options != null ? [var.private_dns_name_options] : []

    content {
      enable_resource_name_dns_aaaa_record = private_dns_name_options.value.enable_resource_name_dns_aaaa_record
      enable_resource_name_dns_a_record    = private_dns_name_options.value.enable_resource_name_dns_a_record
      hostname_type                        = private_dns_name_options.value.hostname_type
    }
  }

  private_ip = var.private_ip

  dynamic "root_block_device" {
    for_each = var.root_block_device != null ? [var.root_block_device] : []

    content {
      delete_on_termination = root_block_device.value.delete_on_termination
      encrypted             = true
      iops                  = root_block_device.value.iops
      kms_key_id            = coalesce(root_block_device.value.kms_key_id, var.kms_key_id)
      tags                  = root_block_device.value.tags
      throughput            = root_block_device.value.throughput
      volume_size           = root_block_device.value.size
      volume_type           = root_block_device.value.type
    }
  }

  secondary_private_ips       = var.secondary_private_ips
  source_dest_check           = var.network_interface != null ? null : var.source_dest_check
  subnet_id                   = var.subnet_id
  tags                        = local.instance_tags
  tenancy                     = var.tenancy
  user_data                   = var.user_data
  user_data_base64            = var.user_data_base64
  user_data_replace_on_change = var.user_data_replace_on_change
  volume_tags                 = var.enable_volume_tags ? merge(var.tags, var.volume_tags, { "Name" = var.name }) : null
  vpc_security_group_ids      = var.network_interface == null ? local.vpc_security_group_ids : null

  dynamic "timeouts" {
    for_each = var.timeouts != null ? [var.timeouts] : []

    content {
      create = timeouts.value.create
      update = timeouts.value.update
      delete = timeouts.value.delete
    }
  }
}

################################################################################
# Instance - Ignore AMI Changes
################################################################################

resource "aws_instance" "ignore_ami" {
  count = local.create && var.ignore_ami_changes && !var.create_spot_instance ? 1 : 0

  region = var.region

  ami                         = local.ami
  associate_public_ip_address = var.associate_public_ip_address
  availability_zone           = var.availability_zone

  dynamic "capacity_reservation_specification" {
    for_each = var.capacity_reservation_specification != null ? [var.capacity_reservation_specification] : []

    content {
      capacity_reservation_preference = capacity_reservation_specification.value.capacity_reservation_preference

      dynamic "capacity_reservation_target" {
        for_each = capacity_reservation_specification.value.capacity_reservation_target != null ? [capacity_reservation_specification.value.capacity_reservation_target] : []

        content {
          capacity_reservation_id                 = capacity_reservation_target.value.capacity_reservation_id
          capacity_reservation_resource_group_arn = capacity_reservation_target.value.capacity_reservation_resource_group_arn
        }
      }
    }
  }

  dynamic "cpu_options" {
    for_each = var.cpu_options != null ? [var.cpu_options] : []

    content {
      amd_sev_snp      = cpu_options.value.amd_sev_snp
      core_count       = cpu_options.value.core_count
      threads_per_core = cpu_options.value.threads_per_core
    }
  }

  credit_specification {
    cpu_credits = local.is_t_instance_type ? var.cpu_credits : null
  }

  disable_api_stop        = var.disable_api_stop
  disable_api_termination = var.disable_api_termination

  # `ebs_block_device` managed by separate resource

  ebs_optimized = var.ebs_optimized

  enclave_options {
    enabled = var.enclave_options_enabled
  }

  enable_primary_ipv6 = var.enable_primary_ipv6

  dynamic "ephemeral_block_device" {
    for_each = var.ephemeral_block_device != null ? var.ephemeral_block_device : {}

    content {
      device_name  = ephemeral_block_device.value.device_name
      no_device    = ephemeral_block_device.value.no_device
      virtual_name = ephemeral_block_device.value.virtual_name
    }
  }

  get_password_data                    = var.get_password_data
  hibernation                          = var.hibernation
  host_id                              = var.host_id
  host_resource_group_arn              = var.host_resource_group_arn
  iam_instance_profile                 = var.create_iam_instance_profile ? aws_iam_instance_profile.this[0].name : var.iam_instance_profile
  instance_initiated_shutdown_behavior = var.instance_initiated_shutdown_behavior

  dynamic "instance_market_options" {
    for_each = var.instance_market_options != null ? [var.instance_market_options] : []

    content {
      market_type = instance_market_options.value.market_type

      dynamic "spot_options" {
        for_each = instance_market_options.value.spot_options != null ? [instance_market_options.value.spot_options] : []

        content {
          instance_interruption_behavior = spot_options.value.instance_interruption_behavior
          max_price                      = spot_options.value.max_price
          spot_instance_type             = spot_options.value.spot_instance_type
          valid_until                    = spot_options.value.valid_until
        }
      }
    }
  }

  instance_type      = var.instance_type
  ipv6_address_count = var.ipv6_address_count
  ipv6_addresses     = var.ipv6_addresses
  key_name           = var.key_name

  dynamic "launch_template" {
    for_each = var.launch_template != null ? [var.launch_template] : []

    content {
      id      = launch_template.value.id
      name    = launch_template.value.name
      version = launch_template.value.version
    }
  }

  dynamic "maintenance_options" {
    for_each = var.maintenance_options != null ? [var.maintenance_options] : []

    content {
      auto_recovery = maintenance_options.value.auto_recovery
    }
  }

  dynamic "metadata_options" {
    for_each = var.metadata_options != null ? [var.metadata_options] : []

    content {
      http_endpoint               = metadata_options.value.http_endpoint
      http_protocol_ipv6          = metadata_options.value.http_protocol_ipv6
      http_put_response_hop_limit = metadata_options.value.http_put_response_hop_limit
      http_tokens                 = metadata_options.value.http_tokens
      instance_metadata_tags      = metadata_options.value.instance_metadata_tags
    }
  }

  monitoring = var.monitoring

  dynamic "network_interface" {
    for_each = var.network_interface != null ? var.network_interface : {}

    content {
      delete_on_termination = network_interface.value.delete_on_termination
      device_index          = coalesce(network_interface.value.device_index, network_interface.key)
      network_card_index    = network_interface.value.network_card_index
      network_interface_id  = network_interface.value.network_interface_id

    }
  }

  placement_group            = var.placement_group
  placement_partition_number = var.placement_partition_number

  dynamic "private_dns_name_options" {
    for_each = var.private_dns_name_options != null ? [var.private_dns_name_options] : []

    content {
      enable_resource_name_dns_aaaa_record = private_dns_name_options.value.enable_resource_name_dns_aaaa_record
      enable_resource_name_dns_a_record    = private_dns_name_options.value.enable_resource_name_dns_a_record
      hostname_type                        = private_dns_name_options.value.hostname_type
    }
  }

  private_ip = var.private_ip

  dynamic "root_block_device" {
    for_each = var.root_block_device != null ? [var.root_block_device] : []

    content {
      delete_on_termination = root_block_device.value.delete_on_termination
      encrypted             = true
      iops                  = root_block_device.value.iops
      kms_key_id            = coalesce(root_block_device.value.kms_key_id, var.kms_key_id)
      tags                  = root_block_device.value.tags
      throughput            = root_block_device.value.throughput
      volume_size           = root_block_device.value.size
      volume_type           = root_block_device.value.type
    }
  }

  secondary_private_ips       = var.secondary_private_ips
  source_dest_check           = var.network_interface != null ? null : var.source_dest_check
  subnet_id                   = var.subnet_id
  tags                        = local.instance_tags
  tenancy                     = var.tenancy
  user_data                   = var.user_data
  user_data_base64            = var.user_data_base64
  user_data_replace_on_change = var.user_data_replace_on_change
  volume_tags                 = var.enable_volume_tags ? merge(var.tags, var.volume_tags, { "Name" = var.name }) : null
  vpc_security_group_ids      = var.network_interface == null ? local.vpc_security_group_ids : null

  dynamic "timeouts" {
    for_each = var.timeouts != null ? [var.timeouts] : []

    content {
      create = timeouts.value.create
      update = timeouts.value.update
      delete = timeouts.value.delete
    }
  }

  lifecycle {
    ignore_changes = [
      ami
    ]
  }
}

################################################################################
# Spot Instance
################################################################################

resource "aws_spot_instance_request" "this" {
  count = local.create && var.create_spot_instance ? 1 : 0

  region = var.region

  # Spot request specific attributes
  instance_interruption_behavior = var.spot_instance_interruption_behavior
  launch_group                   = var.spot_launch_group
  spot_price                     = var.spot_price
  spot_type                      = var.spot_type
  wait_for_fulfillment           = var.spot_wait_for_fulfillment
  valid_from                     = var.spot_valid_from
  valid_until                    = var.spot_valid_until
  # End spot request specific attributes

  ami                         = local.ami
  associate_public_ip_address = var.associate_public_ip_address
  availability_zone           = var.availability_zone

  dynamic "capacity_reservation_specification" {
    for_each = var.capacity_reservation_specification != null ? [var.capacity_reservation_specification] : []

    content {
      capacity_reservation_preference = capacity_reservation_specification.value.capacity_reservation_preference

      dynamic "capacity_reservation_target" {
        for_each = capacity_reservation_specification.value.capacity_reservation_target != null ? [capacity_reservation_specification.value.capacity_reservation_target] : []

        content {
          capacity_reservation_id                 = capacity_reservation_target.value.capacity_reservation_id
          capacity_reservation_resource_group_arn = capacity_reservation_target.value.capacity_reservation_resource_group_arn
        }
      }
    }
  }

  dynamic "cpu_options" {
    for_each = var.cpu_options != null ? [var.cpu_options] : []

    content {
      amd_sev_snp      = cpu_options.value.amd_sev_snp
      core_count       = cpu_options.value.core_count
      threads_per_core = cpu_options.value.threads_per_core
    }
  }

  credit_specification {
    cpu_credits = local.is_t_instance_type ? var.cpu_credits : null
  }

  disable_api_stop        = var.disable_api_stop
  disable_api_termination = var.disable_api_termination

  # `ebs_block_device` managed by separate resource

  ebs_optimized = var.ebs_optimized

  enclave_options {
    enabled = var.enclave_options_enabled
  }

  enable_primary_ipv6 = var.enable_primary_ipv6

  dynamic "ephemeral_block_device" {
    for_each = var.ephemeral_block_device != null ? var.ephemeral_block_device : {}

    content {
      device_name  = ephemeral_block_device.value.device_name
      no_device    = ephemeral_block_device.value.no_device
      virtual_name = ephemeral_block_device.value.virtual_name
    }
  }

  get_password_data                    = var.get_password_data
  hibernation                          = var.hibernation
  host_id                              = var.host_id
  host_resource_group_arn              = var.host_resource_group_arn
  iam_instance_profile                 = var.create_iam_instance_profile ? aws_iam_instance_profile.this[0].name : var.iam_instance_profile
  instance_initiated_shutdown_behavior = var.instance_initiated_shutdown_behavior

  instance_type      = var.instance_type
  ipv6_address_count = var.ipv6_address_count
  ipv6_addresses     = var.ipv6_addresses
  key_name           = var.key_name

  dynamic "launch_template" {
    for_each = var.launch_template != null ? [var.launch_template] : []

    content {
      id      = launch_template.value.id
      name    = launch_template.value.name
      version = launch_template.value.version
    }
  }

  dynamic "maintenance_options" {
    for_each = var.maintenance_options != null ? [var.maintenance_options] : []

    content {
      auto_recovery = maintenance_options.value.auto_recovery
    }
  }

  dynamic "metadata_options" {
    for_each = var.metadata_options != null ? [var.metadata_options] : []

    content {
      http_endpoint               = metadata_options.value.http_endpoint
      http_protocol_ipv6          = metadata_options.value.http_protocol_ipv6
      http_put_response_hop_limit = metadata_options.value.http_put_response_hop_limit
      http_tokens                 = metadata_options.value.http_tokens
      instance_metadata_tags      = metadata_options.value.instance_metadata_tags
    }
  }

  monitoring = var.monitoring

  dynamic "network_interface" {
    for_each = var.network_interface != null ? var.network_interface : {}

    content {
      delete_on_termination = network_interface.value.delete_on_termination
      device_index          = try(network_interface.value.device_index, network_interface.key)
      network_card_index    = network_interface.value.network_card_index
      network_interface_id  = network_interface.value.network_interface_id

    }
  }

  placement_group            = var.placement_group
  placement_partition_number = var.placement_partition_number

  dynamic "private_dns_name_options" {
    for_each = var.private_dns_name_options != null ? [var.private_dns_name_options] : []

    content {
      enable_resource_name_dns_aaaa_record = private_dns_name_options.value.enable_resource_name_dns_aaaa_record
      enable_resource_name_dns_a_record    = private_dns_name_options.value.enable_resource_name_dns_a_record
      hostname_type                        = private_dns_name_options.value.hostname_type
    }
  }

  private_ip = var.private_ip

  dynamic "root_block_device" {
    for_each = var.root_block_device != null ? [var.root_block_device] : []

    content {
      delete_on_termination = root_block_device.value.delete_on_termination
      encrypted             = true
      iops                  = root_block_device.value.iops
      kms_key_id            = coalesce(root_block_device.value.kms_key_id, var.kms_key_id)
      tags                  = root_block_device.value.tags
      throughput            = root_block_device.value.throughput
      volume_size           = root_block_device.value.size
      volume_type           = root_block_device.value.type
    }
  }

  secondary_private_ips       = var.secondary_private_ips
  source_dest_check           = var.network_interface != null ? null : var.source_dest_check
  subnet_id                   = var.subnet_id
  tags                        = local.instance_tags
  tenancy                     = var.tenancy
  user_data                   = var.user_data
  user_data_base64            = var.user_data_base64
  user_data_replace_on_change = var.user_data_replace_on_change
  volume_tags                 = var.enable_volume_tags ? merge(var.tags, var.volume_tags, { "Name" = var.name }) : null
  vpc_security_group_ids      = var.network_interface == null ? local.vpc_security_group_ids : null

  dynamic "timeouts" {
    for_each = var.timeouts != null ? [var.timeouts] : []

    content {
      create = timeouts.value.create
      delete = timeouts.value.delete
    }
  }

  lifecycle {
    ignore_changes = [
      ebs_block_device,
    ]
  }
}

resource "aws_ec2_tag" "spot_instance" {
  for_each = local.create && var.create_spot_instance ? local.instance_tags : {}

  resource_id = aws_spot_instance_request.this[0].spot_instance_id
  key         = each.key
  value       = each.value
}

################################################################################
# EBS Volume(s)
################################################################################

resource "aws_ebs_volume" "this" {
  for_each = var.create && var.ebs_volumes != null ? var.ebs_volumes : {}

  region = var.region

  availability_zone    = local.instance_availability_zone
  encrypted            = true
  final_snapshot       = each.value.final_snapshot
  iops                 = each.value.iops
  kms_key_id           = coalesce(each.value.kms_key_id, var.kms_key_id)
  multi_attach_enabled = each.value.multi_attach_enabled
  outpost_arn          = each.value.outpost_arn
  size                 = each.value.size
  snapshot_id          = each.value.snapshot_id

  tags = merge(
    var.tags,
    var.volume_tags,
    { "Name" = "${var.name}-${each.key}" },
    each.value.tags,
  )

  throughput = each.value.throughput
  type       = each.value.type

  volume_initialization_rate = each.value.volume_initialization_rate
}

resource "aws_volume_attachment" "this" {
  for_each = var.create && var.ebs_volumes != null ? var.ebs_volumes : {}

  region = var.region

  device_name                    = coalesce(each.value.device_name, each.key)
  instance_id                    = local.instance_id
  volume_id                      = aws_ebs_volume.this[each.key].id
  force_detach                   = each.value.force_detach
  skip_destroy                   = each.value.skip_destroy
  stop_instance_before_detaching = each.value.stop_instance_before_detaching
}

################################################################################
# IAM Role / Instance Profile
################################################################################

locals {
  iam_role_name = try(coalesce(var.iam_role_name, var.name), "")
}

data "aws_iam_policy_document" "assume_role_policy" {
  count = var.create && var.create_iam_instance_profile ? 1 : 0

  statement {
    sid     = "EC2AssumeRole"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.${data.aws_partition.current.dns_suffix}"]
    }
  }
}

resource "aws_iam_role" "this" {
  count = var.create && var.create_iam_instance_profile ? 1 : 0

  name        = var.iam_role_use_name_prefix ? null : local.iam_role_name
  name_prefix = var.iam_role_use_name_prefix ? "${local.iam_role_name}-" : null
  path        = var.iam_role_path
  description = var.iam_role_description

  assume_role_policy    = data.aws_iam_policy_document.assume_role_policy[0].json
  permissions_boundary  = var.iam_role_permissions_boundary
  force_detach_policies = true

  tags = merge(var.tags, var.iam_role_tags)
}

resource "aws_iam_role_policy_attachment" "this" {
  for_each = { for k, v in var.iam_role_policies : k => v if var.create && var.create_iam_instance_profile }

  policy_arn = each.value
  role       = aws_iam_role.this[0].name
}

resource "aws_iam_instance_profile" "this" {
  count = var.create && var.create_iam_instance_profile ? 1 : 0

  role = aws_iam_role.this[0].name

  name        = var.iam_role_use_name_prefix ? null : local.iam_role_name
  name_prefix = var.iam_role_use_name_prefix ? "${local.iam_role_name}-" : null
  path        = var.iam_role_path

  tags = merge(var.tags, var.iam_role_tags)

  lifecycle {
    create_before_destroy = true
  }
}

################################################################################
# Security Group
################################################################################

locals {
  create_security_group = var.create && var.create_security_group && var.network_interface == null
  security_group_name   = try(coalesce(var.security_group_name, var.name), "")

  vpc_security_group_ids = local.create_security_group ? concat(var.vpc_security_group_ids, [aws_security_group.this[0].id]) : var.vpc_security_group_ids
}

data "aws_subnet" "this" {
  count = local.create_security_group ? 1 : 0

  region = var.region

  id = var.subnet_id
}

resource "aws_security_group" "this" {
  count = local.create_security_group ? 1 : 0

  region = var.region

  name        = var.security_group_use_name_prefix ? null : local.security_group_name
  name_prefix = var.security_group_use_name_prefix ? "${local.security_group_name}-" : null
  description = var.security_group_description
  vpc_id      = coalesce(var.security_group_vpc_id, data.aws_subnet.this[0].vpc_id)

  tags = merge(
    var.tags,
    { "Name" = local.security_group_name },
    var.security_group_tags
  )

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_egress_rule" "this" {
  for_each = local.create_security_group && var.security_group_egress_rules != null ? var.security_group_egress_rules : {}

  region = var.region

  cidr_ipv4                    = each.value.cidr_ipv4
  cidr_ipv6                    = each.value.cidr_ipv6
  description                  = each.value.description
  from_port                    = try(coalesce(each.value.from_port, each.value.to_port), null)
  ip_protocol                  = each.value.ip_protocol
  prefix_list_id               = each.value.prefix_list_id
  referenced_security_group_id = each.value.referenced_security_group_id
  security_group_id            = aws_security_group.this[0].id

  tags = merge(
    var.tags,
    var.security_group_tags,
    { "Name" = "${local.security_group_name}-${each.key}" },
    each.value.tags,
  )

  to_port = try(coalesce(each.value.to_port, each.value.from_port), null)
}

resource "aws_vpc_security_group_ingress_rule" "this" {
  for_each = local.create_security_group && var.security_group_ingress_rules != null ? var.security_group_ingress_rules : {}

  region = var.region

  cidr_ipv4                    = each.value.cidr_ipv4
  cidr_ipv6                    = each.value.cidr_ipv6
  description                  = each.value.description
  from_port                    = try(coalesce(each.value.from_port, each.value.to_port), null)
  ip_protocol                  = each. value.ip_protocol
  prefix_list_id               = each.value.prefix_list_id
  referenced_security_group_id = each.value.referenced_security_group_id
  security_group_id            = aws_security_group.this[0].id

  tags = merge(
    var.tags,
    var.security_group_tags,
    { "Name" = "${local.security_group_name}-${each.key}" },
    each.value.tags,
  )

  to_port = try(coalesce(each.value.to_port, each.value.from_port), null)
}

################################################################################
# Elastic IP
################################################################################

resource "aws_eip" "this" {
  count = local.create && var.create_eip && !var.create_spot_instance ? 1 : 0

  region = var.region

  domain   = var.eip_domain
  instance = local.instance_id

  tags = merge(var.tags, var.eip_tags)
}


output "id" {
  description = "The ID of the instance"
  value       = local.instance_id
}

output "arn" {
  description = "The ARN of the instance"
  value = try(
    aws_instance.this[0].arn,
    aws_instance.ignore_ami[0].arn,
    aws_spot_instance_request.this[0].arn,
    null,
  )
}

output "capacity_reservation_specification" {
  description = "Capacity reservation specification of the instance"
  value = try(
    aws_instance.this[0].capacity_reservation_specification,
    aws_instance.ignore_ami[0].capacity_reservation_specification,
    aws_spot_instance_request.this[0].capacity_reservation_specification,
    null,
  )
}

output "instance_state" {
  description = "The state of the instance"
  value = try(
    aws_instance.this[0].instance_state,
    aws_instance.ignore_ami[0].instance_state,
    aws_spot_instance_request.this[0].instance_state,
    null,
  )
}

output "outpost_arn" {
  description = "The ARN of the Outpost the instance is assigned to"
  value = try(
    aws_instance.this[0].outpost_arn,
    aws_instance.ignore_ami[0].outpost_arn,
    aws_spot_instance_request.this[0].outpost_arn,
    null,
  )
}

output "password_data" {
  description = "Base-64 encoded encrypted password data for the instance. Useful for getting the administrator password for instances running Microsoft Windows. This attribute is only exported if `get_password_data` is true"
  value = try(
    aws_instance.this[0].password_data,
    aws_instance.ignore_ami[0].password_data,
    aws_spot_instance_request.this[0].password_data,
    null,
  )
}

output "primary_network_interface_id" {
  description = "The ID of the instance's primary network interface"
  value = try(
    aws_instance.this[0].primary_network_interface_id,
    aws_instance.ignore_ami[0].primary_network_interface_id,
    aws_spot_instance_request.this[0].primary_network_interface_id,
    null,
  )
}

output "private_dns" {
  description = "The private DNS name assigned to the instance. Can only be used inside the Amazon EC2, and only available if you've enabled DNS hostnames for your VPC"
  value = try(
    aws_instance.this[0].private_dns,
    aws_instance.ignore_ami[0].private_dns,
    aws_spot_instance_request.this[0].private_dns,
    null,
  )
}

output "public_dns" {
  description = "The public DNS name assigned to the instance. For EC2-VPC, this is only available if you've enabled DNS hostnames for your VPC"
  value = try(
    aws_instance.this[0].public_dns,
    aws_instance.ignore_ami[0].public_dns,
    aws_spot_instance_request.this[0].public_dns,
    null,
  )
}

output "public_ip" {
  description = "The public IP address assigned to the instance, if applicable."
  value = try(
    aws_eip.this[0].public_ip,
    aws_instance.this[0].public_ip,
    aws_instance.ignore_ami[0].public_ip,
    aws_spot_instance_request.this[0].public_ip,
    null,
  )
}

output "private_ip" {
  description = "The private IP address assigned to the instance"
  value = try(
    aws_instance.this[0].private_ip,
    aws_instance.ignore_ami[0].private_ip,
    aws_spot_instance_request.this[0].private_ip,
    null,
  )
}

output "ipv6_addresses" {
  description = "The IPv6 address assigned to the instance, if applicable"
  value = try(
    aws_instance.this[0].ipv6_addresses,
    aws_instance.ignore_ami[0].ipv6_addresses,
    aws_spot_instance_request.this[0].ipv6_addresses,
    [],
  )
}

output "tags_all" {
  description = "A map of tags assigned to the resource, including those inherited from the provider default_tags configuration block"
  value = try(
    aws_instance.this[0].tags_all,
    aws_instance.ignore_ami[0].tags_all,
    aws_spot_instance_request.this[0].tags_all,
    {},
  )
}

output "spot_bid_status" {
  description = "The current bid status of the Spot Instance Request"
  value       = try(aws_spot_instance_request.this[0].spot_bid_status, null)
}

output "spot_request_state" {
  description = "The current request state of the Spot Instance Request"
  value       = try(aws_spot_instance_request.this[0].spot_request_state, null)
}

output "spot_instance_id" {
  description = "The Instance ID (if any) that is currently fulfilling the Spot Instance request"
  value       = try(aws_spot_instance_request.this[0].spot_instance_id, null)
}

output "ami" {
  description = "AMI ID that was used to create the instance"
  value = try(
    aws_instance.this[0].ami,
    aws_instance.ignore_ami[0].ami,
    aws_spot_instance_request.this[0].ami,
    null,
  )
}

output "availability_zone" {
  description = "The availability zone of the created instance"
  value       = local.instance_availability_zone
}

################################################################################
# EBS Volume(s)
################################################################################

output "ebs_volumes" {
  description = "Map of EBS volumes created and their attributes"
  value       = aws_ebs_volume.this
}

################################################################################
# IAM Role / Instance Profile
################################################################################

output "iam_role_name" {
  description = "The name of the IAM role"
  value       = try(aws_iam_role.this[0].name, null)
}

output "iam_role_arn" {
  description = "The Amazon Resource Name (ARN) specifying the IAM role"
  value       = try(aws_iam_role.this[0].arn, null)
}

output "iam_role_unique_id" {
  description = "Stable and unique string identifying the IAM role"
  value       = try(aws_iam_role.this[0].unique_id, null)
}

output "iam_instance_profile_arn" {
  description = "ARN assigned by AWS to the instance profile"
  value       = try(aws_iam_instance_profile.this[0].arn, null)
}

output "iam_instance_profile_id" {
  description = "Instance profile's ID"
  value       = try(aws_iam_instance_profile.this[0].id, null)
}

output "iam_instance_profile_unique" {
  description = "Stable and unique string identifying the IAM instance profile"
  value       = try(aws_iam_instance_profile.this[0].unique_id, null)
}

################################################################################
# Block Devices
################################################################################

output "root_block_device" {
  description = "Root block device information"
  value = try(
    aws_instance.this[0].root_block_device,
    aws_instance.ignore_ami[0].root_block_device,
    aws_spot_instance_request.this[0].root_block_device,
    null
  )
}

output "ebs_block_device" {
  description = "EBS block device information"
  value = try(
    aws_instance.this[0].ebs_block_device,
    aws_instance.ignore_ami[0].ebs_block_device,
    aws_spot_instance_request.this[0].ebs_block_device,
    null
  )
}

output "ephemeral_block_device" {
  description = "Ephemeral block device information"
  value = try(
    aws_instance.this[0].ephemeral_block_device,
    aws_instance.ignore_ami[0].ephemeral_block_device,
    aws_spot_instance_request.this[0].ephemeral_block_device,
    null
  )
}

################################################################################
# Security Group
################################################################################

output "security_group_arn" {
  description = "Amazon Resource Name (ARN) of the security group"
  value       = try(aws_security_group.this[0].arn, null)
}

output "security_group_id" {
  description = "ID of the security group"
  value       = try(aws_security_group.this[0].id, null)
}

variable "create" {
  description = "Whether to create an instance"
  type        = bool
  default     = true
}

variable "name" {
  description = "Name to be used on EC2 instance created"
  type        = string
  default     = ""
}

variable "region" {
  description = "Region where the resource(s) will be managed. Defaults to the Region set in the provider configuration"
  type        = string
  default     = null
}

################################################################################
# Instance
################################################################################

variable "ami" {
  description = "ID of AMI to use for the instance"
  type        = string
  default     = null
}

variable "ami_ssm_parameter" {
  description = "SSM parameter name for the AMI ID. For Amazon Linux AMI SSM parameters see [reference](https://docs.aws.amazon.com/systems-manager/latest/userguide/parameter-store-public-parameters-ami.html)"
  type        = string
  default     = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

variable "ignore_ami_changes" {
  description = "Whether changes to the AMI ID changes should be ignored by Terraform. Note - changing this value will result in the replacement of the instance"
  type        = bool
  default     = false
}

variable "associate_public_ip_address" {
  description = "Whether to associate a public IP address with an instance in a VPC"
  type        = bool
  default     = null
}

variable "availability_zone" {
  description = "AZ to start the instance in"
  type        = string
  default     = null
}

variable "capacity_reservation_specification" {
  description = "Describes an instance's Capacity Reservation targeting option"
  type = object({
    capacity_reservation_preference = optional(string)
    capacity_reservation_target = optional(object({
      capacity_reservation_id                 = optional(string)
      capacity_reservation_resource_group_arn = optional(string)
    }))
  })
  default = null
}

variable "cpu_options" {
  description = "Defines CPU options to apply to the instance at launch time."
  type = object({
    amd_sev_snp      = optional(string)
    core_count       = optional(number)
    threads_per_core = optional(number)
  })
  default = null
}

variable "cpu_credits" {
  description = "The credit option for CPU usage (unlimited or standard)"
  type        = string
  default     = null
}

variable "disable_api_termination" {
  description = "If true, enables EC2 Instance Termination Protection"
  type        = bool
  default     = null
}

variable "disable_api_stop" {
  description = "If true, enables EC2 Instance Stop Protection"
  type        = bool
  default     = null
}

variable "ebs_optimized" {
  description = "If true, the launched EC2 instance will be EBS-optimized"
  type        = bool
  default     = null
}

variable "enclave_options_enabled" {
  description = "Whether Nitro Enclaves will be enabled on the instance. Defaults to `false`"
  type        = bool
  default     = null
}

variable "enable_primary_ipv6" {
  description = "Whether to assign a primary IPv6 Global Unicast Address (GUA) to the instance when launched in a dual-stack or IPv6-only subnet"
  type        = bool
  default     = null
}

variable "ephemeral_block_device" {
  description = "Customize Ephemeral (also known as Instance Store) volumes on the instance"
  type = map(object({
    device_name  = string
    no_device    = optional(bool)
    virtual_name = optional(string)
  }))
  default = null
}

variable "get_password_data" {
  description = "If true, wait for password data to become available and retrieve it"
  type        = bool
  default     = null
}

variable "hibernation" {
  description = "If true, the launched EC2 instance will support hibernation"
  type        = bool
  default     = null
}

variable "host_id" {
  description = "ID of a dedicated host that the instance will be assigned to. Use when an instance is to be launched on a specific dedicated host"
  type        = string
  default     = null
}

variable "host_resource_group_arn" {
  description = "ARN of the host resource group in which to launch the instances. If you specify an ARN, omit the `tenancy` parameter or set it to `host`"
  type        = string
  default     = null
}

variable "iam_instance_profile" {
  description = "IAM Instance Profile to launch the instance with. Specified as the name of the Instance Profile"
  type        = string
  default     = null
}

variable "instance_initiated_shutdown_behavior" {
  description = "Shutdown behavior for the instance. Amazon defaults this to stop for EBS-backed instances and terminate for instance-store instances. Cannot be set on instance-store instance" # https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/terminating-instances.html#Using_ChangingInstanceInitiatedShutdownBehavior
  type        = string
  default     = null
}

variable "instance_market_options" {
  description = "The market (purchasing) option for the instance. If set, overrides the `create_spot_instance` variable"
  type = object({
    market_type = optional(string)
    spot_options = optional(object({
      instance_interruption_behavior = optional(string)
      max_price                      = optional(string)
      spot_instance_type             = optional(string)
      valid_until                    = optional(string)
    }))
  })
  default = null
}

variable "instance_type" {
  description = "The type of instance to start"
  type        = string
  default     = "t3.micro"
}

variable "ipv6_address_count" {
  description = "A number of IPv6 addresses to associate with the primary network interface. Amazon EC2 chooses the IPv6 addresses from the range of your subnet"
  type        = number
  default     = null
}

variable "ipv6_addresses" {
  description = "Specify one or more IPv6 addresses from the range of the subnet to associate with the primary network interface"
  type        = list(string)
  default     = null
}

variable "key_name" {
  description = "Key name of the Key Pair to use for the instance; which can be managed using the `aws_key_pair` resource"
  type        = string
  default     = null
}

variable "launch_template" {
  description = "Specifies a Launch Template to configure the instance. Parameters configured on this resource will override the corresponding parameters in the Launch Template"
  type = object({
    id      = optional(string)
    name    = optional(string)
    version = optional(string)
  })
  default = null
}

variable "maintenance_options" {
  description = "The maintenance options for the instance"
  type = object({
    auto_recovery = optional(string)
  })
  default = null
}

variable "metadata_options" {
  description = "Customize the metadata options of the instance"
  type = object({
    http_endpoint               = optional(string, "enabled")
    http_protocol_ipv6          = optional(string)
    http_put_response_hop_limit = optional(number, 1)
    http_tokens                 = optional(string, "required")
    instance_metadata_tags      = optional(string)
  })
  default = {
    http_endpoint               = "enabled"
    http_put_response_hop_limit = 1
    http_tokens                 = "required"
  }
}

variable "monitoring" {
  description = "If true, the launched EC2 instance will have detailed monitoring enabled"
  type        = bool
  default     = null
}

variable "network_interface" {
  description = "Customize network interfaces to be attached at instance boot time"
  type = map(object({
    delete_on_termination = optional(bool)
    device_index          = optional(number) # Will fall back to use map key as device index
    network_card_index    = optional(number)
    network_interface_id  = string
  }))
  default = null
}

variable "placement_group" {
  description = "The Placement Group to start the instance in"
  type        = string
  default     = null
}

variable "placement_partition_number" {
  description = "Number of the partition the instance is in. Valid only if the `aws_placement_group` resource's `strategy` argument is set to `partition`"
  type        = number
  default     = null
}

variable "private_dns_name_options" {
  description = "Customize the private DNS name options of the instance"
  type = object({
    enable_resource_name_dns_a_record    = optional(bool)
    enable_resource_name_dns_aaaa_record = optional(bool)
    hostname_type                        = optional(string)
  })
  default = null
}

variable "private_ip" {
  description = "Private IP address to associate with the instance in a VPC"
  type        = string
  default     = null
}

variable "root_block_device" {
  description = "Customize details about the root block device of the instance. See Block Devices below for details"
  type = object({
    delete_on_termination = optional(bool)
    encrypted             = optional(bool)
    iops                  = optional(number)
    kms_key_id            = optional(string)
    tags                  = optional(map(string))
    throughput            = optional(number)
    size                  = optional(number)
    type                  = optional(string)
  })
  default = null
}

variable "secondary_private_ips" {
  description = "A list of secondary private IPv4 addresses to assign to the instance's primary network interface (eth0) in a VPC. Can only be assigned to the primary network interface (eth0) attached at instance creation, not a pre-existing network interface i.e. referenced in a `network_interface block`"
  type        = list(string)
  default     = null
}

variable "source_dest_check" {
  description = "Controls if traffic is routed to the instance when the destination address does not match the instance. Used for NAT or VPNs"
  type        = bool
  default     = null
}

variable "subnet_id" {
  description = "The VPC Subnet ID to launch in"
  type        = string
  default     = null
}

variable "tags" {
  description = "A mapping of tags to assign to the resource"
  type        = map(string)
  default     = {}
}

variable "instance_tags" {
  description = "Additional tags for the instance"
  type        = map(string)
  default     = {}
}

variable "tenancy" {
  description = "The tenancy of the instance (if the instance is running in a VPC). Available values: default, dedicated, host"
  type        = string
  default     = null
}

variable "user_data" {
  description = "The user data to provide when launching the instance. Do not pass gzip-compressed data via this argument; see user_data_base64 instead"
  type        = string
  default     = null
}

variable "user_data_base64" {
  description = "Can be used instead of user_data to pass base64-encoded binary data directly. Use this instead of user_data whenever the value is not a valid UTF-8 string. For example, gzip-encoded user data must be base64-encoded and passed via this argument to avoid corruption"
  type        = string
  default     = null
}

variable "user_data_replace_on_change" {
  description = "When used in combination with user_data or user_data_base64 will trigger a destroy and recreate when set to true. Defaults to false if not set"
  type        = bool
  default     = null
}

variable "volume_tags" {
  description = "A mapping of tags to assign to the devices created by the instance at launch time"
  type        = map(string)
  default     = {}
}

variable "enable_volume_tags" {
  description = "Whether to enable volume tags (if enabled it conflicts with root_block_device tags)"
  type        = bool
  default     = true
}

variable "vpc_security_group_ids" {
  description = "A list of security group IDs to associate with"
  type        = list(string)
  default     = []
}

variable "timeouts" {
  description = "Define maximum timeout for creating, updating, and deleting EC2 instance resources"
  type = object({
    create = optional(string)
    update = optional(string)
    delete = optional(string)
  })
  default = null
}

################################################################################
# Spot Instance Request
################################################################################

variable "create_spot_instance" {
  description = "Depicts if the instance is a spot instance"
  type        = bool
  default     = false
}

variable "spot_instance_interruption_behavior" {
  description = "Indicates Spot instance behavior when it is interrupted. Valid values are `terminate`, `stop`, or `hibernate`"
  type        = string
  default     = null
}

variable "spot_launch_group" {
  description = "A launch group is a group of spot instances that launch together and terminate together. If left empty instances are launched and terminated individually"
  type        = string
  default     = null
}

variable "spot_price" {
  description = "The maximum price to request on the spot market. Defaults to on-demand price"
  type        = string
  default     = null
}

variable "spot_type" {
  description = "If set to one-time, after the instance is terminated, the spot request will be closed. Default `persistent`"
  type        = string
  default     = null
}

variable "spot_wait_for_fulfillment" {
  description = "If set, Terraform will wait for the Spot Request to be fulfilled, and will throw an error if the timeout of 10m is reached"
  type        = bool
  default     = null
}

variable "spot_valid_from" {
  description = "The start date and time of the request, in UTC RFC3339 format(for example, YYYY-MM-DDTHH:MM:SSZ)"
  type        = string
  default     = null
}

variable "spot_valid_until" {
  description = "The end date and time of the request, in UTC RFC3339 format(for example, YYYY-MM-DDTHH:MM:SSZ)"
  type        = string
  default     = null
}

################################################################################
# EBS Volume(s)
################################################################################

variable "ebs_volumes" {
  description = "Additional EBS volumes to attach to the instance"
  type = map(object({
    encrypted                  = optional(bool)
    final_snapshot             = optional(bool)
    iops                       = optional(number)
    kms_key_id                 = optional(string)
    multi_attach_enabled       = optional(bool)
    outpost_arn                = optional(string)
    size                       = optional(number)
    snapshot_id                = optional(string)
    tags                       = optional(map(string), {})
    throughput                 = optional(number)
    type                       = optional(string, "gp3")
    volume_initialization_rate = optional(number)
    # Attachment
    device_name                    = optional(string) # Will fall back to use map key as device name
    force_detach                   = optional(bool)
    skip_destroy                   = optional(bool)
    stop_instance_before_detaching = optional(bool)
  }))
  default = null
}

################################################################################
# IAM Role / Instance Profile
################################################################################

variable "create_iam_instance_profile" {
  description = "Determines whether an IAM instance profile is created or to use an existing IAM instance profile"
  type        = bool
  default     = false
}

variable "iam_role_name" {
  description = "Name to use on IAM role created"
  type        = string
  default     = null
}

variable "iam_role_use_name_prefix" {
  description = "Determines whether the IAM role name (`iam_role_name` or `name`) is used as a prefix"
  type        = bool
  default     = true
}

variable "iam_role_path" {
  description = "IAM role path"
  type        = string
  default     = null
}

variable "iam_role_description" {
  description = "Description of the role"
  type        = string
  default     = null
}

variable "iam_role_permissions_boundary" {
  description = "ARN of the policy that is used to set the permissions boundary for the IAM role"
  type        = string
  default     = null
}

variable "iam_role_policies" {
  description = "Policies attached to the IAM role"
  type        = map(string)
  default     = {}
}

variable "iam_role_tags" {
  description = "A map of additional tags to add to the IAM role/profile created"
  type        = map(string)
  default     = {}
}

################################################################################
# Security Group
################################################################################

variable "create_security_group" {
  description = "Determines whether a security group will be created"
  type        = bool
  default     = true
}

variable "security_group_name" {
  description = "Name to use on security group created"
  type        = string
  default     = null
}

variable "security_group_use_name_prefix" {
  description = "Determines whether the security group name (`security_group_name` or `name`) is used as a prefix"
  type        = bool
  default     = true
}

variable "security_group_description" {
  description = "Description of the security group"
  type        = string
  default     = null
}

variable "security_group_vpc_id" {
  description = "VPC ID to create the security group in. If not set, the security group will be created in the default VPC"
  type        = string
  default     = null
}

variable "security_group_tags" {
  description = "A map of additional tags to add to the security group created"
  type        = map(string)
  default     = {}
}

variable "security_group_egress_rules" {
  description = "Egress rules to add to the security group"
  type = map(object({
    cidr_ipv4                    = optional(string)
    cidr_ipv6                    = optional(string)
    description                  = optional(string)
    from_port                    = optional(number)
    ip_protocol                  = optional(string, "tcp")
    prefix_list_id               = optional(string)
    referenced_security_group_id = optional(string)
    tags                         = optional(map(string), {})
    to_port                      = optional(number)
  }))
  default = {
    ipv4_default = {
      cidr_ipv4   = "0.0.0.0/0"
      description = "Allow all IPv4 traffic"
      ip_protocol = "-1"
    }
    ipv6_default = {
      cidr_ipv6   = "2001:db8::/32"
      description = "Allow all IPv6 traffic"
      ip_protocol = "-1"
    }
  }
}

variable "security_group_ingress_rules" {
  description = "Ingress rules to add to the security group"
  type = map(object({
    cidr_ipv4                    = optional(string)
    cidr_ipv6                    = optional(string)
    description                  = optional(string)
    from_port                    = optional(number)
    ip_protocol                  = optional(string, "tcp")
    prefix_list_id               = optional(string)
    referenced_security_group_id = optional(string)
    tags                         = optional(map(string), {})
    to_port                      = optional(number)
  }))
  default = null
}

################################################################################
# Elastic IP
################################################################################

variable "create_eip" {
  description = "Determines whether a public EIP will be created and associated with the instance."
  type        = bool
  default     = false
}

variable "eip_domain" {
  description = "Indicates if this EIP is for use in VPC"
  type        = string
  default     = "vpc"
}

variable "eip_tags" {
  description = "A map of additional tags to add to the eip"
  type        = map(string)
  default     = {}
}

variable "putin_khuylo" {
  description = "Do you agree that Putin doesn't respect Ukrainian sovereignty and territorial integrity? More info: https://en.wikipedia.org/wiki/Putin_khuylo!"
  type        = bool
  default     = true
}

variable "kms_key_id" {
  description = "The ARN of the KMS key to use for encryption of EBS volumes"
  type        = string
  default     = null
}

terraform {
  required_version = ">= 1.5.7"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.28"
    }
  }

  provider_meta "aws" {
    user_agent = [
      "github.com/terraform-aws-modules/terraform-aws-ec2-instance"
    ]
  }
}