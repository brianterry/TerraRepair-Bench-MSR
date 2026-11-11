data "ignition_config" "main" {
  files = ["${compact(list(
    var.dns_server_ip != "" ? join("", data.ignition_file.node_resolv.*.id) : "",
    var.ign_installer_kubelet_env_id,
    var.ign_installer_runtime_mappings_id,
    var.ign_max_user_watches_id,
    var.ign_ntp_dropin_id,
    var.ign_profile_env_id,
    var.ign_s3_puller_id,
    var.ign_systemd_default_env_id,
   ))}",
    "${var.ign_ca_cert_id_list}",
  ]

  systemd = [
    "${var.ign_docker_dropin_id}",
    "${var.ign_k8s_node_bootstrap_service_id}",
    "${var.ign_kubelet_service_id}",
    "${var.ign_locksmithd_service_id}",
    "${var.ign_update_ca_certificates_dropin_id}",
  ]
}

// DNS Server resolution
data "template_file" "node_resolv" {
  count    = "${var.dns_server_ip != "" ? 1 : 0}"
  template = "search us-gov-west-1.compute.internal\nnameserver ${var.dns_server_ip}"
}

data "ignition_file" "node_resolv" {
  count      = "${var.dns_server_ip != "" ? 1 : 0}"
  path       = "/etc/resolv.conf"
  mode       = 0644
  filesystem = "root"

  content {
    content = "${data.template_file.node_resolv.rendered}"
  }
}


resource "aws_s3_bucket_object" "ignition_worker" {
  bucket  = "${var.s3_bucket}"
  key     = "ignition_worker.json"
  content = "${data.ignition_config.main.rendered}"
  acl     = "private"

  server_side_encryption = "aws:kms"
  kms_key_id             = "arn:aws:kms:${local.arn}:key/*"

  tags = "${merge(map(
      "Name", "${var.cluster_name}-ignition-worker",
      "KubernetesCluster", "${var.cluster_name}",
      "tectonicClusterID", "${var.cluster_id}"
    ), var.extra_tags)}"
}

data "ignition_config" "s3" {
  replace {
    source       = "${format("s3://%s/%s", var.s3_bucket, aws_s3_bucket_object.ignition_worker.key)}"
    verification = "sha512-${sha512(data.ignition_config.main.rendered)}"
  }
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


variable "ssh_key" {
  type = "string"
}

variable "vpc_id" {
  type = "string"
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

variable "ec2_type" {
  type = "string"
}

variable "instance_count" {
  type = "string"
}

variable "subnet_ids" {
  type = "list"
}

variable "sg_ids" {
  type        = "list"
  description = "The security group IDs to be applied."
}

variable "load_balancers" {
  description = "List of ELBs to attach all worker instances to."
  type        = "list"
  default     = []
}

variable "extra_tags" {
  description = "Extra AWS tags to be applied to created resources."
  type        = "map"
  default     = {}
}

variable "autoscaling_group_extra_tags" {
  description = "Extra AWS tags to be applied to created autoscaling group resources."
  type        = "list"
  default     = []
}

variable "root_volume_type" {
  type        = "string"
  description = "The type of volume for the root block device."
}

variable "root_volume_size" {
  type        = "string"
  description = "The size of the volume in gigabytes for the root block device."
}

variable "root_volume_iops" {
  type        = "string"
  default     = "100"
  description = "The amount of provisioned IOPS for the root block device."
}

variable "worker_iam_role" {
  type        = "string"
  default     = ""
  description = "IAM role to use for the instance profiles of worker nodes."
}

variable "ign_s3_puller_id" {
  type = "string"
}

variable "s3_bucket" {
  type = "string"
}

variable "dns_server_ip" {
  type    = "string"
  default = ""
}


locals {
  ami_owner = "190570271432"
  arn       = "aws-us-gov"
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

resource "aws_launch_configuration" "worker_conf" {
  instance_type        = "${var.ec2_type}"
  image_id             = "${data.aws_ami.coreos_ami.image_id}"
  name_prefix          = "${var.cluster_name}-worker-"
  key_name             = "${var.ssh_key}"
  security_groups      = ["${var.sg_ids}"]
  iam_instance_profile = "${aws_iam_instance_profile.worker_profile.arn}"
  user_data            = "${data.ignition_config.s3.rendered}"
  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }

  lifecycle {
    create_before_destroy = true

    # Ignore changes in the AMI which force recreation of the resource. This
    # avoids accidental deletion of nodes whenever a new CoreOS Release comes
    # out.
    ignore_changes = ["image_id"]
  }

  root_block_device {
    volume_type = "${var.root_volume_type}"
    volume_size = "${var.root_volume_size}"
    iops        = "${var.root_volume_type == "io1" ? var.root_volume_iops : 0}"
    encrypted   = true
  }
}

resource "aws_launch_template" "worker_template" {
  name = "${var.cluster_name}-worker-template"

  image_id      = "${data.aws_ami.coreos_ami.image_id}"
  instance_type = "${var.ec2_type}"
  key_name      = "${var.ssh_key}"
  security_group_names = ["${var.sg_ids}"]
  iam_instance_profile {
    name = "${aws_iam_instance_profile.worker_profile.name}"
  }
  user_data = "${base64encode(data.ignition_config.s3.rendered)}"
  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }
}

resource "aws_autoscaling_group" "workers" {
  name                 = "${var.cluster_name}-workers"
  desired_capacity     = "${var.instance_count}"
  max_size             = "${var.instance_count * 3}"
  min_size             = "${var.instance_count}"
  vpc_zone_identifier  = ["${var.subnet_ids}"]
  launch_template {
    id      = aws_launch_template.worker_template.id
    version = "$Latest"
  }

  tags = [
    {
      key                 = "Name"
      value               = "${var.cluster_name}-worker"
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

resource "aws_autoscaling_attachment" "workers" {
  count = "${length(var.load_balancers)}"

  autoscaling_group_name = "${aws_autoscaling_group.workers.name}"
  elb                    = "${var.load_balancers[count.index]}"
  lb_target_group_arn   = "${aws_lb_target_group.worker_target_group.arn}"
}

resource "aws_lb_target_group" "worker_target_group" {
  name     = "${var.cluster_name}-worker-target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = "${var.vpc_id}"
}

resource "aws_iam_instance_profile" "worker_profile" {
  name = "${var.cluster_name}-worker-profile"

  role = "${var.worker_iam_role == "" ?
    join("|", aws_iam_role.worker_role.*.name) :
    join("|", data.aws_iam_role.worker_role.*.name)
  }"
}

data "aws_iam_role" "worker_role" {
  count = "${var.worker_iam_role == "" ? 0 : 1}"
  name  = "${var.worker_iam_role}"
}

resource "aws_iam_role" "worker_role" {
  count = "${var.worker_iam_role == "" ? 1 : 0}"
  name  = "${var.cluster_name}-worker-role"
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

resource "aws_iam_role_policy" "worker_policy" {
  count = "${var.worker_iam_role == "" ? 1 : 0}"
  name  = "${var.cluster_name}_worker_policy"
  role  = "${aws_iam_role.worker_role.id}"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "ec2:Describe*",
      "Resource": "arn:aws:ec2:*:*:instance/*"
    },
    {
      "Effect": "Allow",
      "Action": "ec2:AttachVolume",
      "Resource": "arn:aws:ec2:*:*:volume/*"
    },
    {
      "Effect": "Allow",
      "Action": "ec2:DetachVolume",
      "Resource": "arn:aws:ec2:*:*:volume/*"
    },
    {
      "Action": "elasticloadbalancing:*",
      "Resource": "arn:aws:elasticloadbalancing:*:*:loadbalancer/*",
      "Effect": "Allow"
    },
    {
      "Action" : [
        "s3:GetObject"
      ],
      "Resource": "arn:aws:s3:::${var.s3_bucket}/*",
      "Effect": "Allow"
    },
    {
      "Action" : [
        "autoscaling:DescribeAutoScalingGroups",
        "autoscaling:DescribeAutoScalingInstances"
      ],
      "Resource": "arn:aws:autoscaling:*:*:autoScalingGroup:*",
      "Effect": "Allow"
    }
  ]
}
EOF
}