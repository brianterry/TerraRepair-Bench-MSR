data "aws_ec2_instance_type" "master" {
  instance_type = var.work_pc.instance_type
}

locals {
  data_arch = join("", data.aws_ec2_instance_type.master.supported_architectures)
  arch      = local.data_arch == "x86_64"? "amd64" : local.data_arch
}



data "aws_ami" "master" {

  most_recent = true

  filter {
    name = "name"
    values = [
      "ubuntu/images/hvm-ssd/ubuntu-*-${var.work_pc.ubuntu_version}-${local.arch}-server-*"
    ]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"]
}


resource "time_static" "time" {}


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
  "worker_pc_id": {"S": "${local.worker_pc_id}"},
  "worker_pc_ip": {"S": "${local.worker_pc_ip}"},
  "ssh_connection": {"S": "ssh ubuntu@${local.worker_pc_ip} password= ${random_string.ssh.result} "},
  "ssh_password": {"S": "${random_string.ssh.result}"},
  "ssh_login": {"S": "ubuntu"},
  "ssh_ip": {"S": "${local.worker_pc_ip}"},
  "ec2_key": {"S": "${var.work_pc.key_name}"},
  "region": {"S": "${var.region}"}
    }
ITEM

}


resource "aws_iam_role" "fleet_role" {
  for_each = toset(var.work_pc.node_type == "spot"? ["enable"] : [])
  name     = "${local.prefix}-${var.app_name}-worker"
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
  for_each = toset(var.work_pc.node_type == "spot"? ["enable"] : [])
  name     = "${local.prefix}-${var.app_name}-work-pc"
  policy   = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ec2:DescribeImages",
                "ec2:DescribeSubnets",
                "ec2:RequestSpotInstances",
                "ec2:TerminateInstances",
                "ec2:DescribeInstanceStatus",
                "ec2:CreateTags",
                "ec2:RunInstances"
            ],
            "Resource": [
                "*"
            ]
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
                "*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "elasticloadbalancing:RegisterInstancesWithLoadBalancer"
            ],
            "Resource": [
                "arn:aws:elasticloadbalancing:*:*:loadbalancer/*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "elasticloadbalancing:RegisterTargets"
            ],
            "Resource": [
                "arn:aws:elasticloadbalancing:*:*:*/*"
            ]
        }
    ]
}
EOF
}

resource "aws_iam_policy_attachment" "fleet_role" {
  for_each   = toset(var.work_pc.node_type == "spot"? ["enable"] : [])
  name       = "${local.prefix}-${var.app_name}-work-pc"
  policy_arn = aws_iam_policy.fleet_role["enable"].arn
  roles      = [aws_iam_role.fleet_role["enable"].name]
}

resource "aws_launch_template" "master" {
  for_each      = toset(var.work_pc.node_type == "spot"? ["enable"] : [])
  name_prefix   = "${local.prefix}-${var.app_name}"
  image_id      = var.work_pc.ami_id!= ""? var.work_pc.ami_id : data.aws_ami.master.image_id
  instance_type = var.work_pc.instance_type


  user_data = base64encode(templatefile("template/boot_zip.sh", {
    boot_zip = base64gzip(templatefile(var.work_pc.user_data_template, {
      clusters_config     = join(" ", [for key, value in var.work_pc.clusters_config : "${key}=${value}"])
      kubectl_version     = var.work_pc.util.kubectl_version
      ssh_private_key     = var.work_pc.ssh.private_key
      ssh_pub_key         = var.work_pc.ssh.pub_key
      exam_time_minutes   = var.work_pc.exam_time_minutes
      test_url            = var.work_pc.test_url
      task_script_url     = var.work_pc.task_script_url
      ssh_password        = random_string.ssh.result
      ssh_password_enable = var.ssh_password_enable
      hosts               = local.hosts
    }))

  }))
  key_name = var.work_pc.key_name!= ""? var.work_pc.key_name : null
  tags     = local.tags_all_k8_master

  network_interfaces {
    associate_public_ip_address = false
    security_groups             = [aws_security_group.servers.id]
    delete_on_termination       = "true"
    subnet_id                   = local.subnets[var.work_pc.subnet_number]
  }

  block_device_mappings {
    device_name = "/dev/sda1"
    ebs {
      delete_on_termination = "true"
      volume_size           = var.work_pc.root_volume.size
      volume_type           = var.work_pc.root_volume.type
      encrypted             = true
    }
  }

  dynamic "block_device_mappings" {
    for_each = var.work_pc.non_root_volumes

    content {
      device_name = block_device_mappings.key

      ebs {
        delete_on_termination = lookup(block_device_mappings.value, "delete_on_termination", true)
        volume_size           = block_device_mappings.value.size
        volume_type           = block_device_mappings.value.type
        encrypted             = lookup(block_device_mappings.value, "encrypted", false)
      }
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

  lifecycle {
    create_before_destroy = true
  }
}


resource "aws_spot_fleet_request" "master" {
  for_each                      = toset(var.work_pc.node_type == "spot"? ["enable"] : [])
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


data "aws_instances" "spot_fleet" {
  for_each = toset(var.work_pc.node_type == "spot"? ["enable"] : [])
  instance_tags = {
    "aws:ec2spot:fleet-request-id" = aws_spot_fleet_request.master["enable"].id
  }
}


resource "aws_instance" "master" {
  for_each                    = toset(var.work_pc.node_type == "ondemand"? ["enable"] : [])
  iam_instance_profile        = aws_iam_instance_profile.server.id
  associate_public_ip_address = "false"
  ami                         = var.work_pc.ami_id!= ""? var.work_pc.ami_id : data.aws_ami.master.image_id
  instance_type               = var.work_pc.instance_type
  subnet_id                   = local.subnets[var.work_pc.subnet_number]
  key_name                    = var.work_pc.key_name!= ""? var.work_pc.key_name : null
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
  user_data = base64encode(templatefile("template/boot_zip.sh", {
    boot_zip = base64gzip(templatefile(var.work_pc.user_data_template, {
      clusters_config     = join(" ", [for key, value in var.work_pc.clusters_config : "${key}=${value}"])
      kubectl_version     = var.work_pc.util.kubectl_version
      ssh_private_key     = var.work_pc.ssh.private_key
      ssh_pub_key         = var.work_pc.ssh.pub_key
      exam_time_minutes   = var.work_pc.exam_time_minutes
      test_url            = var.work_pc.test_url
      task_script_url     = var.work_pc.task_script_url
      ssh_password        = random_string.ssh.result
      ssh_password_enable = var.ssh_password_enable
      hosts               = local.hosts
    }))

  }))

  tags = local.tags_all
  root_block_device {
    volume_size           = var.work_pc.root_volume.size
    volume_type           = var.work_pc.root_volume.type
    delete_on_termination = true
    tags                  = local.tags_all
    encrypted             = true
  }
}

resource "aws_ebs_volume" "master" {
  for_each = var.work_pc.node_type == "ondemand"? var.work_pc.non_root_volumes : {}

  size              = each.value.size
  type              = each.value.type
  encrypted         = lookup(each.value, "encrypted", false)
  availability_zone = data.aws_subnet.active.availability_zone

  tags = local.tags_all_k8_master
}

data "aws_subnet" "active" {
  id = local.subnets[var.work_pc.subnet_number]
}

resource "aws_volume_attachment" "master" {
  for_each = var.work_pc.node_type == "ondemand"? var.work_pc.non_root_volumes : {}

  device_name = each.key
  volume_id   = aws_ebs_volume.master[each.key].id
  instance_id = aws_instance.master["enable"].id
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
                "cloudwatch:PutMetricData",
                "ec2:DescribeTags",
                "ec2:DescribeRegions",
                "ec2:DescribeHosts",
                "cloudwatch:PutMetricStream",
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
            "Effect": "Allow",
            "Action": [
                "s3:GetObject",
                "s3:ListBucket"
            ],
            "Resource": [
                "arn:aws:s3:::${var.s3_k8s_config}/*",
                "arn:aws:s3:::${var.s3_k8s_config}"
            ]
        }
    ]
}
EOF
}

resource "aws_iam_policy" "server-eks" {
  for_each = toset(var.aws_eks_cluster_eks_cluster_arn == ""? [] : ["enable"])
  name     = "${local.prefix}-${var.app_name}-eks"
  policy   = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "eks:*"
            ],
            "Resource": "${var.aws_eks_cluster_eks_cluster_arn}"
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

resource "aws_iam_policy_attachment" "server-eks" {
  for_each   = toset(var.aws_eks_cluster_eks_cluster_arn == ""? [] : ["enable"])
  name       = "${local.prefix}-${var.app_name}-eks"
  policy_arn = aws_iam_policy.server-eks["enable"].arn
  roles      = [aws_iam_role.server.name]
}


resource "aws_iam_instance_profile" "server" {
  name = "${local.prefix}-${var.app_name}"
  role = aws_iam_role.server.name
}


locals {
  USER_ID       = var.USER_ID == ""? "defaultUser" : var.USER_ID
  ENV_ID        = var.ENV_ID == ""? "defaultId" : var.ENV_ID
  prefix_id     = "${local.USER_ID}_${local.ENV_ID}"
  prefix        = "${local.prefix_id}_${var.prefix}"
  item_id_lock  = "CMDB_lock_${local.USER_ID}_${local.ENV_ID}_${var.app_name}_${var.prefix}"
  item_id_data  = "CMDB_data_${local.USER_ID}_${local.ENV_ID}_${var.app_name}_${var.prefix}"
  subnets_az    = distinct(split(",", (var.subnets_az)))
  subnets       = [for item in local.subnets_az : split("=", item)[0]]
  az            = [for item in local.subnets_az : split("=", item)[1]]
  worker_pc_ssh = var.ssh_password_enable == "true"? "   ssh ubuntu@${local.worker_pc_ip} password= ${random_string.ssh.result}   " : "   ssh ubuntu@${local.worker_pc_ip}   "
  tags_app = {
    "Name"     = "${local.prefix}-${var.app_name}"
    "app_name" = var.app_name
  }
  tags_all = merge(var.tags_common, local.tags_app)
  tags_k8_master = {
    "k8_node_type" = "worker-pc"
    "Name"         = "${local.prefix}-${var.app_name}-worker-pc"
  }
  tags_all_k8_master = var.work_pc.node_type == "spot"? merge(local.tags_all, local.tags_k8_master) : {}

  worker_pc_ip = var.work_pc.node_type == "spot"? join("", data.aws_instances.spot_fleet["enable"].public_ips) : aws_instance.master["enable"].public_ip
  master_ami   = var.work_pc.ami_id!= ""? var.work_pc.ami_id : data.aws_ami.master.image_id
  worker_pc_id = var.work_pc.node_type == "spot"? join("", data.aws_instances.spot_fleet["enable"].ids) : aws_instance.master["enable"].id
  hosts        = join(" ", var.host_list)
}


output "worker_pc_ip" {
  value = var.debug_output == "true"? local.worker_pc_ip : null
}

output "worker_pc_ssh" {
  value = local.worker_pc_ssh
}

output "ssh_user" {
  value = var.debug_output == "true"? "ubuntu" : null
}

output "ssh_password" {
  value = var.debug_output == "true"? random_string.ssh.result : null
}

output "node_type" {
  value = var.debug_output == "true"? var.work_pc.node_type : null
}

output "boot_log" {
  value = "   tail -f /var/log/cloud-init-output.log    "
}

output "worker_reload_bashrc" {
  value = "  source ~/.bashrc   "
}

output "checking_time" {
  value = "  time_left   "
}

output "checking_result" {
  value = "  check_result   "
}

output "backup_kube_config" {
  value = "  /home/ubuntu/.kube/_config   "
}

output "s3_k8s_config" {
  value = var.debug_output == "true"? var.s3_k8s_config : null
}

output "ami_id" {
  value = var.debug_output == "true"? local.master_ami : null
}

output "aws_eks_cluster_eks_cluster_arn" {
  value = var.debug_output == "true"? var.aws_eks_cluster_eks_cluster_arn : null
}

output "instance_type" {
  value = var.debug_output == "true"? var.work_pc.instance_type : null
}

output "kubectl_version" {
  value = var.debug_output == "true"? var.work_pc.util.kubectl_version : null
}

output "prefix" {
  value = var.debug_output == "true"? local.prefix : null
}

output "app_name" {
  value = var.debug_output == "true"? var.app_name : null
}

output "ec2_key" {
  value = length(var.work_pc.key_name) > 0? var.work_pc.key_name : null
}

output "hosts_list" {
  value = var.debug_output == "true"? local.hosts : null
}

output "ssh_password_enable" {
  value = var.debug_output == "true"? var.ssh_password_enable : null
}

output "arch" {
  value = var.debug_output == "true"? local.arch : null
}

output "questions_list" {
  value = length(var.questions_list) > 0? "   ${var.questions_list}    " : null
}

output "ssh_access_cidrs" {
  value = var.debug_output == "true"? var.work_pc.cidrs : null
}

output "solutions_scripts" {
  value = length(var.solutions_scripts) > 0? "   ${var.solutions_scripts}    " : null
}

output "solutions_video" {
  value = length(var.solutions_video) > 0? "   ${var.solutions_video}    " : null
}


resource "random_string" "ssh" {
  length  = 10
  special = false
}


provider "aws" {
  region = var.region
}
provider "aws" {
  region = var.region_cmdb
  alias  = "cmdb"

}


resource "aws_security_group" "servers" {
  name        = "${local.prefix}-mock-${var.app_name}-pc"
  description = "${local.prefix}-mock-${var.app_name}-pc"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = "22"
    to_port     = "22"
    protocol    = "tcp"
    cidr_blocks = var.work_pc.cidrs
    description = "Allow SSH access from specified CIDR blocks"
  }
  ingress {
    from_port   = "9090"
    to_port     = "9090"
    protocol    = "tcp"
    cidr_blocks = var.work_pc.cidrs
    description = "Allow Prometheus access from specified CIDR blocks"
  }

  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    self      = true
    description = "Allow all inbound traffic from within the security group"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = []
    description = "Restrict all outbound traffic"
  }
  tags = local.tags_all

}


variable "region" {}
variable "aws" {}
variable "prefix" {}
variable "USER_ID" {
  type    = string
  default = "defaultUser"
}
variable "ENV_ID" {
  type    = string
  default = "defaultId"
}
variable "tags_common" {
  type = map(string)
}
variable "app_name" {}
variable "vpc_id" {}
variable "subnets_az" {}
variable "time_sleep" {
  default = "30s"
}
variable "aws_eks_cluster_eks_cluster_arn" {
  default = ""
}
variable "ssh_password_enable" {
  default = "true"
}
variable "debug_output" {
  default = "false" # false | true
}
variable "questions_list" {
  default = ""
}

variable "solutions_scripts" {
  default = ""
}

variable "solutions_video" {
  default = ""
}

variable "work_pc" {
  type = object({
    clusters_config    = map(string)
    instance_type      = string
    ami_id             = string
    key_name           = string
    cidrs              = list(string)
    subnet_number      = string
    ubuntu_version     = string
    user_data_template = string
    task_script_url    = string # url for run additional script
    node_type          = string # spot ar ondemand
    ssh = object({
      private_key = string
      pub_key     = string
    })
    test_url          = string
    exam_time_minutes = string
    util = object({
      kubectl_version = string
    })
    root_volume = object({
      type = string
      size = string
    })
    non_root_volumes = map(object({
      delete_on_termination = optional(bool),
      size                  = number,
      type                  = string,
      encrypted             = optional(bool)
    }))
  })
}

variable "STACK_NAME" {
  type    = string
  default = ""
}

variable "STACK_TASK" {
  type    = string
  default = ""
}

variable "host_list" {
  type    = list(string)
  default = []
}