data "ignition_config" "main" {
  files = ["${compact(list(
    data.ignition_file.detect_master.id,
    data.ignition_file.init_assets.id,
    data.ignition_file.rm_assets.id,
    var.ign_installer_kubelet_env_id,
    var.ign_installer_runtime_mappings_id,
    var.ign_max_user_watches_id,
    var.ign_nfs_config_id,
    var.ign_ntp_dropin_id,
    var.ign_profile_env_id,
    var.ign_s3_puller_id,
    var.ign_systemd_default_env_id,
   ))}",
    "${var.ign_ca_cert_id_list}",
  ]

  systemd = ["${compact(list(
    var.ign_bootkube_path_unit_id,
    var.ign_bootkube_service_id,
    var.ign_docker_dropin_id,
    var.ign_init_assets_service_id,
    var.ign_iscsi_service_id,
    var.ign_k8s_node_bootstrap_service_id,
    var.ign_kubelet_service_id,
    var.ign_locksmithd_service_id,
    var.ign_rm_assets_path_unit_id,
    var.ign_rm_assets_service_id,
    var.ign_tectonic_path_unit_id,
    var.ign_tectonic_service_id,
    var.ign_update_ca_certificates_dropin_id,
   ))}"]
}

data "template_file" "detect_master" {
  template = "${file("${path.module}/resources/detect-master.sh")}"

  vars {
    load_balancer_name = "${format("%s-%s", var.cluster_name, var.private_endpoints ? "int" : "ext")}"
  }
}

data "ignition_file" "detect_master" {
  filesystem = "root"
  path       = "/opt/detect-master.sh"
  mode       = 0755

  content {
    content = "${data.template_file.detect_master.rendered}"
  }
}

data "template_file" "init_assets" {
  template = "${file("${path.module}/resources/init-assets.sh")}"

  vars {
    assets_s3_location = "${var.assets_s3_location}"
    awscli_image       = "${var.container_images["awscli"]}"
    cluster_name       = "${var.cluster_name}"
  }
}

data "ignition_file" "init_assets" {
  filesystem = "root"
  path       = "/opt/init-assets.sh"
  mode       = 0755

  content {
    content = "${data.template_file.init_assets.rendered}"
  }
}

data "template_file" "rm_assets" {
  template = "${file("${path.module}/resources/rm-assets.sh")}"

  vars {
    assets_s3_location = "${var.assets_s3_location}"
    awscli_image       = "${var.container_images["awscli"]}"
    cluster_name       = "${var.cluster_name}"
  }
}

data "ignition_file" "rm_assets" {
  filesystem = "root"
  path       = "/opt/rm-assets.sh"
  mode       = 0755

  content {
    content = "${data.template_file.rm_assets.rendered}"
  }
}


resource "aws_s3_bucket_object" "ignition_master" {
  bucket  = "${var.s3_bucket}"
  key     = "ignition_master.json"
  content = "${data.ignition_config.main.rendered}"
  acl     = "private"

  server_side_encryption = "AES256"

  tags = "${merge(map(
      "Name", "${var.cluster_name}-ignition-master",
      "KubernetesCluster", "${var.cluster_name}",
      "tectonicClusterID", "${var.cluster_id}"
    ), var.extra_tags)}"
}

data "ignition_config" "s3" {
  replace {
    source       = "${format("s3://%s/%s", var.s3_bucket, aws_s3_bucket_object.ignition_master.key)}"
    verification = "sha512-${sha512(data.ignition_config.main.rendered)}"
  }
}


locals {
  ami_owner = "595879546273"
  arn       = "aws"
}

data "aws_ami" "coreos_ami" {
  filter {
    name   = "name"
    values = ["CoreOS-${var.container_linux_channel}-${var.container_linux_version}-*"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "owner-id"
    values = ["${local.ami_owner}"]
  }
}

resource "aws_autoscaling_group" "masters" {
  name                 = "${var.cluster_name}-masters"
  desired_capacity     = "${var.instance_count}"
  max_size             = "${var.instance_count * 3}"
  min_size             = "${var.instance_count}"
  launch_template {
    name       = "${var.cluster_name}-master-template"
    version    = "\${latest}"
  }
  vpc_zone_identifier  = ["${var.subnet_ids}"]

  load_balancers = ["${var.aws_lbs}"]

  tags = [
    {
      key                 = "Name"
      value               = "${var.cluster_name}-master"
      propagate_at_launch = true
    },
    {
      key                 = "kubernetes.io/cluster/${var.cluster_name}"
      value               = "owned"
      propagate_at_launch = true
    },
    {
      key                 = "tectonicClusterID"
      value               = "${var.cluster_id}"
      propagate_at_launch = true
    },
    "${var.autoscaling_group_extra_tags}",
  ]

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_launch_template" "master_template" {
  name_prefix                 = "${var.cluster_name}-master-"
  image_id                    = "${coalesce(var.ec2_ami, data.aws_ami.coreos_ami.image_id)}"
  instance_type               = "${var.ec2_type}"
  key_name                    = "${var.ssh_key}"
  security_groups             = ["${var.master_sg_ids}"]
  iam_instance_profile        = "${aws_iam_instance_profile.master_profile.arn}"
  associate_public_ip_address  = false
  user_data                   = "${data.ignition_config.s3.rendered}"
  block_device_mappings {
    device_name = "/dev/xvda"
    no_device   = true
  }

  root_block_device {
    volume_type = "${var.root_volume_type}"
    volume_size = "${var.root_volume_size}"
    iops        = "${var.root_volume_type == "io1"? var.root_volume_iops : 0}"
    encrypted   = true
  }

  metadata_options {
    http_endpoint                       = "enabled"
    http_put_response_hop_limit         = 2
    http_tokens                         = "required"
  }
}

resource "aws_iam_instance_profile" "master_profile" {
  name = "${var.cluster_name}-master-profile"

  role = "${var.master_iam_role == ""?
    join("|", aws_iam_role.master_role.*.name) :
    join("|", data.aws_iam_role.master_role.*.name)
  }"
}

data "aws_iam_role" "master_role" {
  count = "${var.master_iam_role == "" ? 0 : 1}"
  name  = "${var.master_iam_role}"
}

resource "aws_iam_role" "master_role" {
  count = "${var.master_iam_role == ""? 1 : 0}"
  name  = "${var.cluster_name}-master-role"
  path  = "/"

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
}

resource "aws_iam_role_policy" "master_policy" {
  count = "${var.master_iam_role == "" ? 1 : 0}"
  name  = "${var.cluster_name}_master_policy"
  role  = "${aws_iam_role.master_role.id}"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "ec2:DescribeInstances",
      "Resource": "*",
      "Effect": "Allow"
    },
    {
      "Action": "elasticloadbalancing:DescribeLoadBalancers",
      "Resource": "*",
      "Effect": "Allow"
    },
    {
      "Action" : [
        "s3:GetObject",
        "s3:HeadObject",
        "s3:ListBucket"
      ],
      "Resource": "arn:${local.arn}:s3:::*",
      "Effect": "Allow"
    },
    {
      "Action" : [
        "autoscaling:DescribeAutoScalingGroups",
        "autoscaling:DescribeAutoScalingInstances"
      ],
      "Resource": "*",
      "Effect": "Allow"
    }
  ]
}
EOF
}


# This file is supposed to be symlinked in consuming modules

variable "ign_max_user_watches_id" {
  type = "string"
}

variable "ign_docker_dropin_id" {
  type = "string"
}

variable "ign_kubelet_service_id" {
  type = "string"
}

variable "ign_locksmithd_service_id" {
  type = "string"
}

variable "ign_installer_runtime_mappings_id" {
  type = "string"
}

variable "ign_installer_kubelet_env_id" {
  type = "string"
}

variable "ign_k8s_node_bootstrap_service_id" {
  type = "string"
}

variable "ign_update_ca_certificates_dropin_id" {
  type = "string"
}

variable "ign_ca_cert_id_list" {
  type        = "list"
  description = "The list of public CA certificate ignition file IDs."
}

variable "ign_iscsi_service_id" {
  type = "string"
}

variable "ign_profile_env_id" {
  type = "string"
}

variable "ign_systemd_default_env_id" {
  type = "string"
}

variable "ign_ntp_dropin_id" {
  type = "string"
}

variable "ign_nfs_config_id" {
  type        = "string"
  description = "Content of NFS configuration file."
}


variable "assets_s3_location" {
  type        = "string"
  description = "Location on S3 of the Bootkube/Tectonic assets to use (bucket/key)"
}

variable "autoscaling_group_extra_tags" {
  description = "Extra AWS tags to be applied to created autoscaling group resources."
  type        = "list"
  default     = []
}

variable "base_domain" {
  type        = "string"
  description = "Domain on which the ELB records will be created"
}

variable "container_linux_channel" {
  type = "string"
}

variable "container_linux_version" {
  type = "string"
}

variable "cluster_id" {
  type = "string"
}

variable "cluster_name" {
  type = "string"
}

variable "container_images" {
  description = "Container images to use"
  type        = "map"
}

variable "ec2_type" {
  type = "string"
}

variable "extra_tags" {
  description = "Extra AWS tags to be applied to created resources."
  type        = "map"
  default     = {}
}

variable "ign_s3_puller_id" {
  type = "string"
}

variable "ec2_ami" {
  type    = "string"
  default = ""
}

variable "instance_count" {
  type = "string"
}

variable "master_iam_role" {
  type        = "string"
  default     = ""
  description = "IAM role to use for the instance profiles of master nodes."
}

variable "master_sg_ids" {
  type        = "list"
  description = "The security group IDs to be applied to the master nodes."
}

variable "private_endpoints" {
  description = "If set to true, private-facing ingress resources are created."
  default     = true
}

variable "public_endpoints" {
  description = "If set to true, public-facing ingress resources are created."
  default     = true
}

variable "aws_lbs" {
  description = "List of aws_lb IDs for the Console & APIs"
  type        = "list"
  default     = []
}

variable "root_volume_iops" {
  type        = "string"
  default     = "100"
  description = "The amount of provisioned IOPS for the root block device."
}

variable "root_volume_size" {
  type        = "string"
  description = "The size of the volume in gigabytes for the root block device."
}

variable "root_volume_type" {
  type        = "string"
  description = "The type of volume for the root block device."
}

variable "ssh_key" {
  type = "string"
}

variable "subnet_ids" {
  type = "list"
}

variable "ign_bootkube_service_id" {
  type        = "string"
  description = "The ID of the bootkube systemd service unit"
}

variable "ign_bootkube_path_unit_id" {
  type = "string"
}

variable "ign_tectonic_service_id" {
  type        = "string"
  description = "The ID of the tectonic installer systemd service unit"
}

variable "ign_tectonic_path_unit_id" {
  type = "string"
}

variable "ign_init_assets_service_id" {
  type = "string"
}

variable "ign_rm_assets_service_id" {
  type = "string"
}

variable "ign_rm_assets_path_unit_id" {
  type = "string"
}

variable "s3_bucket" {
  type = "string"
}