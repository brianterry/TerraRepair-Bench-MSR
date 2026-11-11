data "aws_ec2_instance_type" "master" {
  instance_type = var.k8s_master.instance_type
}

data "aws_ami" "master" {

  most_recent = true

  filter {
    name   = "name"
    values = join("", data.aws_ec2_instance_type.master.supported_architectures) == "x86_64" ? ["ubuntu/images/hvm-ssd/ubuntu-*-${var.k8s_master.ubuntu_version}-amd64-server-*"] : ["ubuntu/images/hvm-ssd/ubuntu-*-${var.k8s_master.ubuntu_version}-arm64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"]
}


data "aws_ec2_instance_type" "worker" {
  for_each      = var.k8s_worker
  instance_type = each.value.instance_type
}

locals {
  worker_ami_arh = {
    for key, instance in var.k8s_worker :
    key => {
      name   = join("", data.aws_ec2_instance_type.master.supported_architectures) == "x86_64" ? "amd64" : "arm64"
      filter = join("", data.aws_ec2_instance_type.master.supported_architectures) == "x86_64" ? "ubuntu/images/hvm-ssd/ubuntu-*-${instance.ubuntu_version}-amd64-server-*" : "ubuntu/images/hvm-ssd/ubuntu-*-${instance.ubuntu_version}-arm64-server-*"
    }
  }
}

#output "worker_arch" {
#  value = local.worker_ami_arh
#}
data "aws_ami" "worker" {
  for_each    = var.k8s_worker
  most_recent = true

  filter {
    name   = "name"
    values = [local.worker_ami_arh["${each.key}"].filter]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"]
}


data "aws_dynamodb_table" "cmdb" {
  name     = var.backend_dynamodb_table
  provider = aws.cmdb
}

resource "aws_dynamodb_table_item" "cmdb" {
  provider   = aws.cmdb
  hash_key   = "LockID"
  table_name = data.aws_dynamodb_table.cmdb.name
  item       = <<ITEM
{
  "LockID": {"S": "${local.item_id_lock}"},
  "time_stamp": {"S": "${time_static.time.unix}"},
  "USER_ID": {"S": "${local.USER_ID}"},
  "ENV_ID": {"S": "${local.ENV_ID}"},
  "STACK_NAME": {"S": "${var.STACK_NAME}"},
  "STACK_TASK": {"S": "${var.STACK_TASK}"},
  "region": {"S": "${var.region}"}

    }
ITEM

}

resource "aws_dynamodb_table_item" "cmdb_data" {
  provider   = aws.cmdb
  hash_key   = "LockID"
  table_name = data.aws_dynamodb_table.cmdb.name
  item       = <<ITEM
{
  "LockID": {"S": "${local.item_id_data}"},
  "time_stamp": {"S": "${time_static.time.unix}"},
  "USER_ID": {"S": "${local.USER_ID}"},
  "ENV_ID": {"S": "${local.ENV_ID}"},
  "STACK_NAME": {"S": "${var.STACK_NAME}"},
  "STACK_TASK": {"S": "${var.STACK_TASK}"},
  "master_instance_id": {"S": "${local.master_instance_id}"},
  "master_ip": {"S": "${local.master_ip_public}"},
  "worker_node_ids": {"S": "${local.worker_node_ids}"},
  "worker_node_ips_private": {"S": "${local.worker_node_ips_private}"},
  "worker_node_ips_public": {"S": "${local.worker_node_ips_public}"},
  "ssh_password": {"S": "${random_string.ssh.result}"},
  "ssh_login": {"S": "ubuntu"},
  "ec2_key": {"S": "${var.k8s_master.key_name}"},
  "region": {"S": "${var.region}"}
    }
ITEM

}


data "aws_vpc" "vpc" {
  id = var.vpc_id
}


resource "aws_iam_role" "fleet_role" {
  for_each = toset(var.node_type == "spot" ? ["enable"] : [])
  name     = "${local.prefix}-${var.app_name}-${var.cluster_name}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "spotfleet.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_policy" "fleet_role" {
  for_each = toset(var.node_type == "spot" ? ["enable"] : [])
  name     = "${local.prefix}-${var.app_name}-${var.cluster_name}"
  policy   = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ec2:DescribeImages",
                "ec2:DescribeSubnets",
                "ec2:DescribeInstanceStatus"
            ],
            "Resource": [
                "*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "ec2:RequestSpotInstances"
            ],
            "Resource": [
                "arn:aws:ec2:*:*:spot-instances-request/*"
            ],
            "Condition": {
                "Bool": {
                    "aws:SecureTransport": "true"
                }
            }
        },
        {
            "Effect": "Allow",
            "Action": [
                "ec2:TerminateInstances"
            ],
            "Resource": [
                "arn:aws:ec2:*:*:instance/*"
            ],
            "Condition": {
                "Bool": {
                    "aws:SecureTransport": "true"
                }
            }
        },
        {
            "Effect": "Allow",
            "Action": [
                "ec2:CreateTags"
            ],
            "Resource": [
                "arn:aws:ec2:*:*:instance/*",
                "arn:aws:ec2:*:*:volume/*",
                "arn:aws:ec2:*:*:spot-instances-request/*",
                "arn:aws:ec2:*:*:network-interface/*"
            ],
            "Condition": {
                "Bool": {
                    "aws:SecureTransport": "true"
                }
            }
        },
        {
            "Effect": "Allow",
            "Action": [
                "ec2:RunInstances"
            ],
            "Resource": [
                "arn:aws:ec2:*:*:instance/*",
                "arn:aws:ec2:*:*:volume/*",
                "arn:aws:ec2:*:*:network-interface/*",
                "arn:aws:ec2:*:*:key-pair/*",
                "arn:aws:ec2:*:*:security-group/*",
                "arn:aws:ec2:*:*:subnet/*",
                "arn:aws:ec2:*:*:image/*",
                "arn:aws:ec2:*:*:launch-template/*"
            ],
            "Condition": {
                "Bool": {
                    "aws:SecureTransport": "true"
                }
            }
        },
        {
            "Effect": "Allow",
            "Action": "iam:PassRole",
            "Condition": {
                "StringEquals": {
                    "iam:PassedToService": [
                        "ec2.amazonaws.com",
                        "ec2.amazonaws.com.cn"
                    ]
                }
            },
            "Resource": [
                "arn:aws:iam::*:role/${local.prefix}-${var.app_name}"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "elasticloadbalancing:RegisterInstancesWithLoadBalancer"
            ],
            "Resource": [
                "arn:aws:elasticloadbalancing:*:*:loadbalancer/*"
            ],
            "Condition": {
                "Bool": {
                    "aws:SecureTransport": "true"
                }
            }
        },
        {
            "Effect": "Allow",
            "Action": [
                "elasticloadbalancing:RegisterTargets"
            ],
            "Resource": [
                "arn:aws:elasticloadbalancing:*:*:*/*"
            ],
            "Condition": {
                "Bool": {
                    "aws:SecureTransport": "true"
                }
            }
        }
    ]
}
EOF
}

resource "aws_iam_policy_attachment" "fleet_role" {
  for_each   = toset(var.node_type == "spot" ? ["enable"] : [])
  name       = "${local.prefix}-${var.app_name}-${var.cluster_name}"
  policy_arn = aws_iam_policy.fleet_role["enable"].arn
  roles      = [aws_iam_role.fleet_role["enable"].name]
}


resource "aws_launch_template" "master" {
  for_each      = toset(var.node_type == "spot" ? ["enable"] : [])
  name_prefix   = "${local.prefix}-${var.app_name}"
  image_id      = local.master_ami
  instance_type = var.k8s_master.instance_type
  user_data = base64encode(templatefile("template/boot_zip.sh", {
    boot_zip = base64gzip(templatefile(var.k8s_master.user_data_template, {
      worker_join         = local.worker_join
      k8s_config          = local.k8s_config
      external_ip         = local.external_ip
      k8_version          = var.k8s_master.k8_version
      runtime             = var.k8s_master.runtime
      utils_enable        = var.k8s_master.utils_enable
      pod_network_cidr    = var.k8s_master.pod_network_cidr
      runtime_script      = file(var.k8s_master.runtime_script)
      task_script_url     = var.k8s_master.task_script_url
      calico_url          = var.k8s_master.calico_url
      ssh_private_key     = var.k8s_master.ssh.private_key
      ssh_pub_key         = var.k8s_master.ssh.pub_key
      ssh_password        = random_string.ssh.result
      ssh_password_enable = var.ssh_password_enable
    }))

  }))
  key_name = var.k8s_master.key_name != "" ? var.k8s_master.key_name : null
  tags     = local.tags_all_k8_master

  network_interfaces {
    associate_public_ip_address = false
    security_groups             = [aws_security_group.servers.id]
    delete_on_termination       = "true"
    subnet_id                   = local.subnets[var.k8s_master.subnet_number]
  }

  block_device_mappings {
    device_name = "/dev/sda1"
    ebs {
      delete_on_termination = "true"
      volume_size           = var.k8s_master.root_volume.size
      volume_type           = var.k8s_master.root_volume.type
      encrypted             = true

    }

  }
  tag_specifications {
    resource_type = "instance"
    tags          = local.tags_all_k8_master
  }

  tag_specifications {
    resource_type = "volume"
    tags          = local.tags_all_k8_master
  }

  iam_instance_profile {
    name = aws_iam_instance_profile.server.name
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  lifecycle {
    create_before_destroy = true
  }
}


resource "aws_spot_fleet_request" "master" {
  for_each                      = toset(var.node_type == "spot" ? ["enable"] : [])
  iam_fleet_role                = aws_iam_role.fleet_role["enable"].arn
  target_capacity               = 1
  wait_for_fulfillment          = true
  terminate_instances_on_delete = true
  launch_template_config {
    launch_template_specification {
      id      = aws_launch_template.master["enable"].id
      version = aws_launch_template.master["enable"].latest_version
    }
  }
}


data "aws_instances" "spot_fleet_master" {
  for_each = toset(var.node_type == "spot" ? ["enable"] : [])
  instance_tags = {
    "aws:ec2spot:fleet-request-id" = aws_spot_fleet_request.master["enable"].id
  }
}


resource "aws_instance" "master" {
  for_each                    = toset(var.node_type == "ondemand" ? ["enable"] : [])
  iam_instance_profile        = aws_iam_instance_profile.server.id
  associate_public_ip_address = false
  ebs_optimized               = true
  monitoring                  = true
  ami                         = local.master_ami
  instance_type               = var.k8s_master.instance_type
  subnet_id                   = local.subnets[var.k8s_master.subnet_number]
  key_name                    = var.k8s_master.key_name != "" ? var.k8s_master.key_name : null
  security_groups             = [aws_security_group.servers.id]
  lifecycle {
    ignore_changes = [
      instance_type,
      user_data,
      root_block_device,
      key_name,
      security_groups
    ]
  }
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }
  user_data = base64encode(templatefile("template/boot_zip.sh", {
    boot_zip = base64gzip(templatefile(var.k8s_master.user_data_template, {
      worker_join         = local.worker_join
      k8s_config          = local.k8s_config
      external_ip         = local.external_ip
      k8_version          = var.k8s_master.k8_version
      runtime             = var.k8s_master.runtime
      utils_enable        = var.k8s_master.utils_enable
      pod_network_cidr    = var.k8s_master.pod_network_cidr
      runtime_script      = file(var.k8s_master.runtime_script)
      task_script_url     = var.k8s_master.task_script_url
      calico_url          = var.k8s_master.calico_url
      ssh_private_key     = var.k8s_master.ssh.private_key
      ssh_pub_key         = var.k8s_master.ssh.pub_key
      ssh_password        = random_string.ssh.result
      ssh_password_enable = var.ssh_password_enable
    }))

  }))


  tags = local.tags_all
  root_block_device {
    volume_size           = var.k8s_master.root_volume.size
    volume_type           = var.k8s_master.root_volume.type
    delete_on_termination = true
    tags                  = local.tags_all
    encrypted             = true
  }


}



resource "aws_launch_template" "worker" {
  for_each      = local.k8s_worker_spot
  name_prefix   = "${local.prefix}-${var.app_name}"
  image_id      = each.value.ami_id != "" ? each.value.ami_id : data.aws_ami.worker["${each.key}"].image_id
  instance_type = each.value.instance_type

  user_data = base64encode(templatefile("template/boot_zip.sh", {
    boot_zip = base64gzip(templatefile(each.value.user_data_template, {
      worker_join         = local.worker_join
      k8s_config          = local.k8s_config
      k8_version          = each.value.k8_version
      runtime             = each.value.runtime
      runtime_script      = file(each.value.runtime_script)
      task_script_url     = each.value.task_script_url
      node_name           = each.key
      node_labels         = each.value.node_labels
      ssh_private_key     = each.value.ssh.private_key
      ssh_pub_key         = each.value.ssh.pub_key
      ssh_password        = random_string.ssh.result
      ssh_password_enable = var.ssh_password_enable
    }))

  }))


  key_name = each.value.key_name != "" ? each.value.key_name : null
  tags     = merge(var.tags_common, local.tags_app, { "Name" = "${local.prefix}-${var.app_name}-worker-${each.key}" })
  network_interfaces {
    associate_public_ip_address = false
    security_groups             = [aws_security_group.servers.id]
    delete_on_termination       = "true"
    subnet_id                   = local.subnets[each.value.subnet_number]
  }

  block_device_mappings {
    device_name = "/dev/sda1"
    ebs {
      delete_on_termination = "true"
      volume_size           = each.value.root_volume.size
      volume_type           = each.value.root_volume.type
      encrypted             = true

    }

  }
  tag_specifications {
    resource_type = "instance"
    tags          = merge(var.tags_common, local.tags_app, { "Name" = "${local.prefix}-${var.app_name}-worker-${each.key}" })
  }

  tag_specifications {
    resource_type = "volume"
    tags          = merge(var.tags_common, local.tags_app, { "Name" = "${local.prefix}-${var.app_name}-worker-${each.key}" })
  }

  iam_instance_profile {
    name = aws_iam_instance_profile.server.name
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  lifecycle {
    create_before_destroy = true
  }
}


resource "aws_spot_fleet_request" "worker" {
  for_each                      = local.k8s_worker_spot
  iam_fleet_role                = aws_iam_role.fleet_role["enable"].arn
  target_capacity               = 1
  wait_for_fulfillment          = true
  terminate_instances_on_delete = true
  launch_template_config {
    launch_template_specification {
      id      = aws_launch_template.worker["${each.key}"].id
      version = aws_launch_template.worker["${each.key}"].latest_version
    }
  }
}


data "aws_instances" "spot_fleet_worker" {
  for_each = local.k8s_worker_spot
  instance_tags = {
    "aws:ec2spot:fleet-request-id" = aws_spot_fleet_request.worker["${each.key}"].id
  }
}


resource "aws_instance" "worker" {
  for_each                    = local.k8s_worker_ondemand
  iam_instance_profile        = aws_iam_instance_profile.server.id
  associate_public_ip_address = false
  ebs_optimized               = true
  monitoring                  = true
  ami                         = each.value.ami_id != "" ? each.value.ami_id : data.aws_ami.worker["${each.key}"].image_id
  instance_type               = each.value.instance_type
  subnet_id                   = local.subnets[each.value.subnet_number]
  key_name                    = each.value.key_name != "" ? each.value.key_name : null
  security_groups             = [aws_security_group.servers.id]
  lifecycle {
    ignore_changes = [
      instance_type,
      user_data,
      root_block_device,
      key_name,
      security_groups
    ]
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  user_data = base64encode(templatefile("template/boot_zip.sh", {
    boot_zip = base64gzip(templatefile(each.value.user_data_template, {
      worker_join         = local.worker_join
      k8s_config          = local.k8s_config
      k8_version          = each.value.k8_version
      runtime             = each.value.runtime
      runtime_script      = file(each.value.runtime_script)
      task_script_url     = each.value.task_script_url
      node_name           = each.key
      node_labels         = each.value.node_labels
      ssh_private_key     = each.value.ssh.private_key
      ssh_pub_key         = each.value.ssh.pub_key
      ssh_password        = random_string.ssh.result
      ssh_password_enable = var.ssh_password_enable
    }))

  }))


  tags = local.tags_all
  root_block_device {
    volume_size           = each.value.root_volume.size
    volume_type           = each.value.root_volume.type
    delete_on_termination = true
    tags                  = local.tags_all
    encrypted             = true
  }

}


resource "aws_eip" "master" {
  for_each = toset(var.k8s_master.eip == "true" ? ["enable"] : [])
  domain   = "vpc"
  instance = local.master_instance_id
  tags     = local.tags_all_k8_master
}

resource "aws_eip_association" "master" {
  for_each      = toset(var.k8s_master.eip == "true" ? ["enable"] : [])
  instance_id   = local.master_instance_id
  allocation_id = aws_eip.master["enable"].id
}


resource "aws_iam_role" "server" {
  name               = "${local.prefix}-${var.app_name}"
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
  tags               = local.tags_all

}

resource "aws_iam_policy" "server" {
  name   = "${local.prefix}-${var.app_name}"
  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "VisualEditor0",
            "Effect": "Allow",
            "Action": [
                "ec2:DescribeAddresses",
                "ec2:DescribeInstances",
                "ec2:DescribeTags",
                "ec2:DescribeRegions",
                "ec2:DescribeHosts",
                "ec2:DescribeVolumeStatus",
                "ec2:DescribeNetworkInterfaces",
                "ec2:DescribeVpcs",
                "ec2:DescribeVolumes",
                "ec2:DescribeSubnets",
                "ec2:DescribeInstanceStatus"
            ],
            "Resource": "*"
        },
        {
            "Sid": "CloudWatchPutMetricData",
            "Effect": "Allow",
            "Action": [
                "cloudwatch:PutMetricData"
            ],
            "Resource": "*",
            "Condition": {
                "Bool": {
                    "aws:SecureTransport": "true"
                }
            }
        },
        {
            "Sid": "CloudWatchPutMetricStream",
            "Effect": "Allow",
            "Action": [
                "cloudwatch:PutMetricStream"
            ],
            "Resource": "arn:aws:cloudwatch:*:*:metric-stream/*",
            "Condition": {
                "Bool": {
                    "aws:SecureTransport": "true"
                }
            }
        },
        {
            "Sid": "S3ConfigAccess",
            "Effect": "Allow",
            "Action": [
                "s3:GetObject",
                "s3:PutObject",
                "s3:DeleteObject",
                "s3:GetObjectVersion",
                "s3:ListBucket",
                "s3:GetBucketLocation"
            ],
            "Resource": [
                "arn:aws:s3:::${var.s3_k8s_config}/*",
                "arn:aws:s3:::${var.s3_k8s_config}"
            ],
            "Condition": {
                "Bool": {
                    "aws:SecureTransport": "true"
                }
            }
        }
    ]
}
EOF
}


resource "aws_iam_policy_attachment" "server" {
  name       = "${local.prefix}-${var.app_name}"
  policy_arn = aws_iam_policy.server.arn
  roles      = [aws_iam_role.server.name]
}
resource "aws_iam_instance_profile" "server" {
  name = "${local.prefix}-${var.app_name}"
  role = aws_iam_role.server.name
}


locals {
  USER_ID      = var.USER_ID == "" ? "defaultUser" : var.USER_ID
  ENV_ID       = var.ENV_ID == "" ? "defaultId" : var.ENV_ID
  prefix_id    = "${local.USER_ID}_${local.ENV_ID}"
  prefix       = "${local.prefix_id}_${var.prefix}"
  item_id_lock = "CMDB_lock_${local.USER_ID}_${local.ENV_ID}_${var.app_name}_${var.prefix}"
  item_id_data = "CMDB_data_${local.USER_ID}_${local.ENV_ID}_${var.app_name}_${var.prefix}"
  subnets_az   = distinct(split(",", (var.subnets_az)))
  subnets      = [for item in local.subnets_az : split("=", item)[0]]
  az           = [for item in local.subnets_az : split("=", item)[1]]
  tags_app = {
    "Name"     = "${local.prefix}-${var.app_name}"
    "app_name" = var.app_name
  }
  tags_all = merge(var.tags_common, local.tags_app)
  tags_k8_master = {
    "k8_node_type" = "master"
    "Name"         = "${local.prefix}-${var.app_name}-master"
  }
  tags_all_k8_master = var.node_type == "spot" ? merge(local.tags_all, local.tags_k8_master) : {}

  tags_k8_worker = {
    "k8_node_type" = "worker"
    "Name"         = "${local.prefix}-${var.app_name}-worker"
  }
  tags_all_k8_worker = merge(local.tags_all, local.tags_k8_worker)
  worker_join        = "${var.s3_k8s_config}/config/${local.USER_ID}/${local.ENV_ID}/${var.cluster_name}-${local.target_time_stamp}/worker_join"
  k8s_config         = "${var.s3_k8s_config}/config/${local.USER_ID}/${local.ENV_ID}/${var.cluster_name}-${local.target_time_stamp}/config"

  worker_nodes = var.node_type == "spot" ? {
    for key, instance in data.aws_instances.spot_fleet_worker :
    key => {
      private_ip     = join("", instance.private_ips)
      public_ip      = join("", instance.public_ips)
      runtime        = var.k8s_worker[key].runtime
      labels         = var.k8s_worker[key].node_labels
      id             = join("", instance.ids)
      ami            = aws_launch_template.worker["${key}"].image_id
      ubuntu_version = var.k8s_worker["${key}"].ubuntu_version
      instance_type  = var.k8s_worker["${key}"].instance_type
    }
    } : {
    for key, instance in aws_instance.worker :
    key => {
      private_ip     = instance.private_ip
      public_ip      = instance.public_ip
      runtime        = var.k8s_worker[key].runtime
      labels         = var.k8s_worker[key].node_labels
      id             = instance.id
      ami            = instance.ami
      ubuntu_version = var.k8s_worker["${key}"].ubuntu_version
      instance_type  = var.k8s_worker["${key}"].instance_type
    }
  }

  worker_node_ids         = join(" ", [for node in local.worker_nodes : node.id])
  worker_node_ips_public  = join(" ", [for node in local.worker_nodes : node.public_ip])
  worker_node_ips_private = join(" ", [for node in local.worker_nodes : node.private_ip])

  master_ip            = var.node_type == "spot" ? join("", data.aws_instances.spot_fleet_master["enable"].public_ips) : aws_instance.master["enable"].public_ip
  master_ip_public     = var.k8s_master.eip == "true" ? aws_eip.master["enable"].public_ip : local.master_ip
  external_ip          = var.k8s_master.eip == "true" ? aws_eip.master["enable"].public_ip : ""
  master_instance_id   = var.node_type == "spot" ? join("", data.aws_instances.spot_fleet_master["enable"].ids) : aws_instance.master["enable"].id
  master_local_ip      = var.node_type == "spot" ? join("", data.aws_instances.spot_fleet_master["enable"].private_ips) : aws_instance.master["enable"].private_ip
  k8s_worker_ondemand  = var.node_type == "ondemand" ? var.k8s_worker : {}
  k8s_worker_spot      = var.node_type == "spot" ? var.k8s_worker : {}
  master_ami           = var.k8s_master.ami_id != "" ? var.k8s_master.ami_id : data.aws_ami.master.image_id
  master_instance_type = var.k8s_master.instance_type

  hosts_worker_node = [for key, value in local.worker_nodes : "${var.cluster_name}_node_${key}=${value.private_ip}"]
  hosts_master_node = ["${var.cluster_name}_controlPlane_1=${local.master_local_ip}"]
  hosts             = concat(local.hosts_master_node, local.hosts_worker_node)
}


output "master_external_ip" {
  value = local.master_ip_public
}

output "cluster" {
  value = var.cluster_name
}
output "master_local_ip" {
  value = local.master_local_ip
}
output "node_type" {
  value = var.node_type
}
output "worker_join" {
  value = "s3://${local.worker_join}"
}

output "k8s_config" {
  value = "s3://${local.k8s_config}"
}
output "k8_master_version" {
  value = var.k8s_master.k8_version
}

output "master_ssh" {
  value = "ssh ubuntu@${local.master_ip_public}  password= ${random_string.ssh.result}  "
}

output "eip" {
  value = var.k8s_master.eip
}

output "check_node_status" {
  value = "tail -f /var/log/cloud-init-output.log "
}

output "s3_k8s_config" {
  value = local.k8s_config
}

output "worker_nodes" {
  value = local.worker_nodes
}

output "ami_id_master" {
  value = local.master_ami
}

output "master_instance_type" {
  value = local.master_instance_type
}

output "worker_reload_bashrc" {
  value = "  source ~/.bashrc   "
}
output "ec2_key" {
  value = var.k8s_master.key_name
}

output "ssh_password" {
  value = "  ${random_string.ssh.result}   "
}

output "hosts_worker_node" {
  value = local.hosts_worker_node
}
output "hosts_master_node" {
  value = local.hosts_master_node
}

output "hosts" {
  value = local.hosts
}

output "ssh_password_enable" {
  value = var.ssh_password_enable
}


resource "random_string" "ssh" {
  length  = 10
  special = false
}


provider "aws" {
  region = var.region
}

provider "aws" {
  alias  = "cmdb"
  region = var.region_cmdb
}


resource "aws_security_group" "servers" {
  name        = "${local.prefix}-k8-self-managment"
  description = "${local.prefix}-k8-self-managment"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = "22"
    to_port     = "22"
    protocol    = "tcp"
    cidr_blocks = var.k8s_master.cidrs
    description = "ssh"
  }

  ingress {
    from_port   = "30000"
    to_port     = "32767"
    protocol    = "tcp"
    cidr_blocks = var.k8s_master.cidrs
    description = "NodePort k8s"
  }

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
    cidr_blocks = var.k8s_master.cidrs
    description = "Allow all traffic from self and specified CIDRs"
  }

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [data.aws_vpc.vpc.cidr_block]
    description = "Allow all traffic from VPC CIDR"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = concat([data.aws_vpc.vpc.cidr_block], var.k8s_master.cidrs)
    description = "Allow outbound traffic to VPC and specified CIDRs"
  }
  tags = local.tags_all

}



resource "time_static" "time" {
}

locals {
  time_stamp        = timestamp()
  target_time_stamp = sum([tonumber(time_static.time.unix), tonumber("10")])
}


variable "region" {}
variable "aws" {}
variable "prefix" {}
variable "tags_common" {
  type = map(string)
}
variable "USER_ID" {
  type    = string
  default = "defaultUser"
}
variable "ENV_ID" {
  type    = string
  default = "defaultId"
}
variable "app_name" {}
variable "vpc_id" {}
variable "subnets_az" {}
# k8_version    https://packages.cloud.google.com/apt/dists/kubernetes-xenial/main/binary-amd64/Packages
variable "cluster_name" { type = string }
variable "time_sleep" {
  default = "30s"
}
variable "ssh_password_enable" {
  default = "true"
}
variable "node_type" { type = string }
variable "k8s_master" {
  type = object({
    instance_type      = string
    ami_id             = string
    ubuntu_version     = string
    key_name           = string
    cidrs              = list(string)
    subnet_number      = string
    user_data_template = string
    k8_version         = string
    runtime            = string
    runtime_script     = string
    utils_enable       = string
    pod_network_cidr   = string
    calico_url         = string
    task_script_url    = string # url for run additional script
    eip                = string # true or ...
    ssh = object({
      private_key = string
      pub_key     = string
    })
    root_volume = object({
      type = string
      size = string
    })
  })
}

variable "k8s_worker" {
  type = map(object({
    instance_type      = string
    ami_id             = string
    ubuntu_version     = string
    key_name           = string
    cidrs              = list(string)
    subnet_number      = string
    user_data_template = string
    k8_version         = string
    runtime            = string
    runtime_script     = string
    task_script_url    = string # url for run additional script
    node_labels        = string
    ssh = object({
      private_key = string
      pub_key     = string
    })
    root_volume = object({
      type = string
      size = string
    })
  }))
}

variable "STACK_NAME" {
  type    = string
  default = ""
}

variable "STACK_TASK" {
  type    = string
  default = ""
}