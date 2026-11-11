```hcl
data "ignition_config" "etcd" {
  count = "${length(var.external_endpoints) == 0? var.instance_count : 0}"

  systemd = [
    "${data.ignition_systemd_unit.locksmithd.*.id[count.index]}",
    "${var.ign_etcd_dropin_id_list[count.index]}",
  ]

  files = ["${compact(list(
    var.ign_ntp_dropin_id,
    var.ign_profile_env_id,
    var.ign_systemd_default_env_id,
    var.dns_server_ip!= ""? join("", data.ignition_file.node_resolv.*.id) : "",
   ))}",
    "${var.ign_etcd_crt_id_list}",
  ]
}

data "ignition_systemd_unit" "locksmithd" {
  count = "${length(var.external_endpoints) == 0? var.instance_count : 0}"

  name    = "locksmithd.service"
  enabled = true

  dropin = [
    {
      name = "40-etcd-lock.conf"

      content = <<EOF
[Service]
Environment=REBOOT_STRATEGY=etcd-lock
${var.tls_enabled ? "Environment=\"LOCKSMITHD_ETCD_CAFILE=/etc/ssl/etcd/ca.crt\"" : ""}
${var.tls_enabled ? "Environment=\"LOCKSMITHD_ETCD_KEYFILE=/etc/ssl/etcd/client.key\"" : ""}
${var.tls_enabled ? "Environment=\"LOCKSMITHD_ETCD_CERTFILE=/etc/ssl/etcd/client.crt\"" : ""}
Environment="LOCKSMITHD_ENDPOINT=${var.tls_enabled ? "https" : "http"}://${var.cluster_name}-etcd-${count.index}.${var.base_domain}:2379"
EOF
    },
  ]
}

// DNS Server resolution
data "template_file" "node_resolv" {
  count    = "${var.dns_server_ip!= ""? 1 : 0}"
  template = "search us-gov-west-1.compute.internal\nnameserver ${var.dns_server_ip}"
}

data "ignition_file" "node_resolv" {
  count      = "${var.dns_server_ip!= ""? 1 : 0}"
  path       = "/etc/resolv.conf"
  mode       = 0644
  filesystem = "root"

  content {
    content = "${data.template_file.node_resolv.rendered}"
  }
}


resource "aws_s3_bucket_object" "ignition_etcd" {
  count = "${length(var.external_endpoints) == 0? var.instance_count : 0}"

  bucket  = "${var.s3_bucket}"
  key     = "ignition_etcd_${count.index}.json"
  content = "${data.ignition_config.etcd.*.rendered[count.index]}"
  acl     = "private"

  server_side_encryption = "aws:kms"
  server_side_encryption_kms_key_id = "alias/aws/s3"

  tags = "${merge(map(
      "Name", "${var.cluster_name}-ignition-etcd-${count.index}",
      "KubernetesCluster", "${var.cluster_name}",
      "tectonicClusterID", "${var.cluster_id}"
    ), var.extra_tags)}"
}

data "ignition_config" "s3" {
  count = "${length(var.external_endpoints) == 0? var.instance_count : 0}"

  replace {
    source       = "${format("s3://%s/%s", var.s3_bucket, aws_s3_bucket_object.ignition_etcd.*.key[count.index])}"
    verification = "sha512-${sha512(data.ignition_config.etcd.*.rendered[count.index])}"
  }
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

filter {
  name   = "root-device-type"
  values = ["ebs"]
}

resource "aws_iam_instance_profile" "etcd" {
  count = "${length(var.external_endpoints) == 0? 1 : 0}"
  name  = "${var.cluster_name}-etcd-profile"

  role = "${var.etcd_iam_role == ""?
    join("|", aws_iam_role.etcd_role.*.name) :
    join("|", data.aws_iam_role.etcd_role.*.name)
  }"
}

data "aws_iam_role" "etcd_role" {
  count = "${var.etcd_iam_role == "" ? 0 : 1}"
  name  = "${var.etcd_iam_role}"
}

resource "aws_iam_role" "etcd_role" {
  count = "${length(var.external_endpoints) == 0 && var.etcd_iam_role == "" ? 1 : 0}"
  name  = "${var.cluster_name}-etcd-role"
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

resource "aws_iam_role_policy" "etcd" {
  count = "${var.etcd_iam_role == "" ? 1 : 0}"
  name  = "${var.cluster_name}_etcd_policy"
  role  = "${aws_iam_role.etcd_role.id}"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "ec2:Describe*",
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": "ec2:AttachVolume",
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": "ec2:DetachVolume",
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject"
      ],
      "Resource": "arn:${local.arn}:s3:::*",
      "Condition": {
        "StringEquals": {
          "s3:x-amz-meta-custom-key": "value"
        }
      }
    }
  ]
}
EOF
}

resource "aws_instance" "etcd_node" {
  count = "${length(var.external_endpoints) == 0? var.instance_count : 0}"
  ami   = "${data.aws_ami.coreos_ami.image_id}"

  iam_instance_profile   = "${aws_iam_instance_profile.etcd.name}"
  instance_type          = "${var.ec2_type}"
  key_name               = "${var.ssh_key}"
  subnet_id              = "${element(var.subnets, count.index)}"
  user_data              = "${data.ignition_config.s3.*.rendered[count.index]}"
  vpc_security_group_ids = ["${var.sg_ids}"]

  lifecycle {
    # Ignore changes in the AMI which force recreation of the resource. This
    # avoids accidental deletion of nodes whenever a new CoreOS Release comes
    # out.
    ignore_changes = ["ami"]
  }

  tags = "${merge(map(
      "Name", "${var.cluster_name}-etcd-${count.index}",
      "kubernetes.io/cluster/${var.cluster_name}", "owned",
      "tectonicClusterID", "${var.cluster_id}"
    ), var.extra_tags)}"

  root_block_device {
    volume_type = "${var.root_volume_type}"
    volume_size = "${var.root_volume_size}"
    iops        = "${var.root_volume_type == "io1"? var.root_volume_iops : var.root_volume_type == "gp2"? min(10000, max(100, 3 * var.root_volume_size)) : 0}"
    encrypted   = true
  }

  volume_tags = "${merge(map(
    "Name", "${var.cluster_name}-etcd-${count.index}-vol",
    "kubernetes.io/cluster/${var.cluster_name}", "owned",
    "tectonicClusterID", "${var.cluster_id}"
  ), var.extra_tags)}"

  metadata_options {
    http_tokens          = "required"
    http_endpoint        = "optional"
    http_put_response_hop_limit = 2
    http_protocols       = ["http", "https"]
  }

  monitoring {
    enabled = true
  }

  block_device_mapping {
    device_name = "/dev/sda1"
    ebs {
      volume_size = 10
      volume_type = "gp3"
      iops        = 3000
      encrypted   = true
    }
  }

  block_device_mapping {
    device_name = "/dev/sdb"
    ebs {
      volume_size = 100
      volume_type = "gp3"
      iops        = 3000
      encrypted   = true
    }
  }

  block_device_mapping {
    device_name = "/dev/sdc"
    ebs {
      volume_size = 200
      volume_type = "gp3"
      iops        = 3000
      encrypted   = true
    }
  }

  block_device_mapping {
    device_name = "/dev/sdd"
    ebs {
      volume_size = 300
      volume_type = "gp3"
      iops        = 3000
      encrypted   = true
    }
  }

  block_device_mapping {
    device_name = "/dev/sde"
    ebs {
      volume_size = 400
      volume_type = "gp3"
      iops        = 3000
      encrypted   = true
    }
  }

  block_device_mapping {
    device_name = "/dev/sdf"
    ebs {
      volume_size = 500
      volume_type = "gp3"
      iops        = 3000
      encrypted   = true
    }
  }

  block_device_mapping {
    device_name = "/dev/sdg"
    ebs {
      volume_size = 600
      volume_type = "gp3"
      iops        = 3000
      encrypted   = true
    }
  }

  block_device_mapping {
    device_name = "/dev/sdh"
    ebs {
      volume_size = 700
      volume_type = "gp3"
      iops        = 3000
      encrypted   = true
    }
  }

  block_device_mapping {
    device_name = "/dev/sdi"
    ebs {
      volume_size = 800
      volume_type = "gp3"
      iops        = 3000
      encrypted   = true
    }
  }

  block_device_mapping {
    device_name = "/dev/sdj"
    ebs {
      volume_size = 900
      volume_type = "gp3"
      iops        = 3000
      encrypted   = true
    }
  }

  block_device_mapping {
    device_name = "/dev/sdk"
    ebs {
      volume_size = 1000
      volume_type = "gp3"
      iops        = 3000
      encrypted   = true
    }
  }

  block_device_mapping {
    device_name = "/dev/sdl"
    ebs {
      volume_size = 1100
      volume_type = "gp3"
      iops        = 3000
      encrypted   = true
    }
  }

  block_device_mapping {
    device_name = "/dev/sdm"
    ebs {
      volume_size = 1200
      volume_type = "gp3"
      iops        = 3000
      encrypted   = true
    }
  }

  block_device_mapping {
    device_name = "/dev/sdn"
    ebs {
      volume_size = 1300
      volume_type = "gp3"
      iops        = 3000
      encrypted   = true
    }
  }

  block_device_mapping {
    device_name = "/dev/sdo"
    ebs {
      volume_size = 1400
      volume_type = "gp3"
      iops        = 3000
      encrypted   = true
    }
  }

  block_device_mapping {
    device_name = "/dev/sdp"
    ebs {
      volume_size = 1500
      volume_type = "gp3"
      iops        = 3000
      encrypted   = true
    }
  }

  block_device_mapping {
    device_name = "/dev/sdq"
    ebs {
      volume_size = 1600
      volume_type = "gp3"
      iops        = 3000
      encrypted   = true
    }
  }

  block_device_mapping {
    device_name = "/dev/sdr"
    ebs {
      volume_size = 1700
      volume_type = "gp3"
      iops        = 3000
      encrypted   = true
    }
  }

  block_device_mapping {
    device_name = "/dev/sds"
    ebs {
      volume_size = 1800
      volume_type = "gp3"
      iops        = 3000
      encrypted   = true
    }
  }

  block_device_mapping {
    device_name = "/dev/sdt"
    ebs {
      volume_size = 1900
      volume_type = "gp3"
      iops        = 3000
      encrypted   = true
    }
  }

  block_device_mapping {
    device_name = "/dev/sdu"
    ebs {
      volume_size = 2000
      volume_type = "gp3"
      iops        = 3000
      encrypted   = true
    }
  }

  block_device_mapping {
    device_name = "/dev/sdv"
    ebs {
      volume_size = 2100
      volume_type = "gp3"
      iops        = 3000
      encrypted   = true
    }
  }

  block_device_mapping {
    device_name = "/dev/sdw"
    ebs {
      volume_size = 2200
      volume_type = "gp3"
      iops        = 3000
      encrypted   = true
    }
  }

  block_device_mapping {
    device_name = "/dev/sdx"
    ebs {
      volume_size = 2300
      volume_type = "gp3"
      iops        = 3000
      encrypted   = true
    }
  }

  block_device_mapping {
    device_name = "/dev/sdy"
    ebs {
      volume_size = 2400
      volume_type = "gp3"
      iops        = 3000
      encrypted   = true
    }
  }

  block_device_mapping {
    device_name = "/dev/sdz"
    ebs {
      volume_size = 2500
      volume_type = "gp3"
      iops        = 3000
      encrypted   = true
    }
  }

  block_device_mapping {
    device_name = "/dev/sda"
    ebs {
      volume_size = 2600
      volume_type = "gp3"
      iops        = 3000
      encrypted   = true
    }
  }

  block_device_mapping {
    device_name = "/dev/sdb"
    ebs {
      volume_size = 2700
      volume_type = "gp3"
      iops        = 3000
      encrypted   = true
    }
  }

  block_device_mapping {
    device_name = "/dev/sdc"
    ebs {
      volume_size = 2800
      volume_type = "gp3"
      iops        = 3000
      encrypted   = true
    }
  }

  block_device_mapping {
    device_name = "/dev/sdd"
    ebs {
      volume_size = 2900
      volume_type = "gp3"
      iops        = 3000
      encrypted   = true
    }
  }

  block_device_mapping {
    device_name = "/dev/sde"
    ebs {
      volume_size = 3000
      volume_type = "gp3"
      iops        = 3000
      encrypted   = true
    }
  }

  block_device_mapping {
    device_name = "/dev/sdf"
    ebs {
      volume_size = 3100
      volume_type = "gp3"
      iops        = 3000
      encrypted   = true
    }
  }

  block_device_mapping {
    device_name = "/dev/sdg"
    ebs {
      volume_size = 3200
      volume_type = "gp3"
      iops        = 3000
      encrypted   = true
    }
  }

  block_device_mapping {
    device_name = "/dev/sdh"
    ebs {
      volume_size = 3300
      volume_type = "gp3"
      iops        = 3000
      encrypted   = true
    }
  }

  block_device_mapping {
    device_name = "/dev/sdi"
    ebs {
      volume_size = 3400
      volume_type = "gp3"
      iops        = 3000
      encrypted   = true
    }
  }

  block_device_mapping {
    device_name = "/dev/sdj"
    ebs {
      volume_size = 3500
      volume_type = "gp3"
      iops        = 3000
      encrypted   = true
    }
  }

  block_device_mapping {
    device_name = "/dev/sdk"
    ebs {
      volume_size = 3600
      volume_type = "gp3"
      iops        = 3000
      encrypted   = true
    }
  }

  block_device_mapping {
    device_name = "/dev/sdl"
    ebs {
      volume_size = 3700
      volume_type = "gp3"
      iops        = 3000
      encrypted   = true
    }
  }

  block_device_mapping {
    device_name = "/dev/sdm"
    ebs {
      volume_size = 3800
      volume_type = "gp3"
      iops        = 3000
      encrypted   = true
    }
  }

  block_device_mapping {
    device_name = "/dev/sdn"
    ebs {
      volume_size = 3900
      volume_type = "gp3"
      iops        = 3000
      encrypted   = true
    }
  }

  block_device_mapping {
    device_name = "/dev/sdo"
    ebs {
      volume_size = 4000
      volume_type = "gp3"
      iops        = 3000
      encrypted   = true
    }
  }

  block_device_mapping {
    device_name = "/dev/sdp"
    ebs {
      volume_size = 4100
      volume_type = "gp3"
      iops        = 3000
      encrypted   = true
    }
  }

  block_device_mapping {
    device_name = "/dev/sdq"
    ebs {
      volume_size = 4200
      volume_type = "gp3"
      iops        = 3000
      encrypted   = true
    }
  }

  block_device_mapping {
    device_name = "/dev/sdr"
    ebs {
      volume_size = 4300
      volume_type = "gp3"
      iops        = 3000
      encrypted   = true
    }
  }

  block_device_mapping {
    device_name = "/dev/sds"
    ebs {
      volume_size = 4400
      volume_type = "gp3"
      iops        = 3000
      encrypted   = true
    }
  }

  block_device_mapping {
    device_name = "/dev/sdt"
    ebs {
      volume_size = 4500
      volume_type = "gp3"
      iops        = 3000
      encrypted   = true
    }
  }

  block_device_mapping {
    device_name = "/dev/sdu"
    ebs {
      volume_size = 4600
      volume_type = "gp3"
      iops        = 3000
      encrypted   = true
    }
  }

  block_device_mapping {
    device_name = "/dev/sdv"
    ebs {
      volume_size = 4700
      volume_type = "gp3"
      iops        = 3000
      encrypted   = true
    }
  }

  block_device_mapping {
    device_name = "/dev/sdw"
    ebs {
      volume_size = 4800
      volume_type = "gp3"
      iops        = 3000
      encrypted   = true
    }
  }

  block_device_mapping {
    device_name = "/dev/sdx"
    ebs {
      volume_size = 4900
      volume_type = "gp3"
      iops        = 3000
      encrypted   = true
    }
  }

  block_device_mapping {
    device_name = "/dev/sdy"
    ebs {
      volume_size = 5000
      volume_type = "gp3"
      iops        = 3000
      encrypted   = true
    }
  }

  block_device_mapping {
    device_name = "/dev/sdz"
    ebs {
      volume_size = 5100
      volume_type = "gp3"
      iops        = 3000
      encrypted   = true
    }
  }

  block_device_mapping {
    device_name = "/dev/sda"
    ebs {
      volume_size = 5200
      volume_type = "gp3"
      iops        = 3000
      encrypted   = true
    }
  }

  block_device_mapping {
    device_name = "/dev/sdb"
    ebs {
      volume_size = 5300
      volume_type = "gp3"
      iops        = 3000
      encrypted   = true
    }
  }

  block_device_mapping {
    device_name = "/dev/sdc"
    ebs {
      volume_size = 5400
      volume_type = "gp3"
      iops        = 3000
      encrypted   = true
    }
  }

  block_device_mapping {
    device_name = "/dev/sdd"
    ebs {
      volume_size = 5500
      volume_type = "gp3"
      iops        = 3000
      encrypted   = true
    }
  }

  block_device_mapping {
    device_name = "/dev/sde"
    ebs {
      volume_size = 5600
      volume_type = "gp3"
      iops        = 3000
      encrypted   = true
    }
  }

  block_device_mapping {
    device_name = "/dev/sdf"
    ebs {
      volume_size = 5700
      volume_type = "gp3"
      iops        = 3000
      encrypted   = true
    }
  }

  block_device_mapping {
    device_name = "/dev/sdg"
    ebs {
      volume_size = 5800
      volume_type = "gp3"
      iops        = 3000
      encrypted   = true
    }
  }

  block_device_mapping {
    device_name = "/dev/sdh"
    ebs {
      volume_size = 5900
      volume_type = "gp3"
      iops        = 3000
      encrypted   = true
    }
  }

  block_device_mapping {
    device_name = "/dev/sdi"
    ebs {
      volume_size = 6000
      volume_type = "gp3"
      iops        = 3000
      encrypted   = true
    }
  }

  block_device_mapping {
    device_name = "/dev/sdj"
    ebs {
      volume_size = 6100
      volume_type = "gp3"
      iops        = 3000
      encrypted   = true
    }
  }

  block_device_mapping {
    device_name = "/dev/sdk"
    ebs {
      volume_size = 6200
      volume_type = "gp3"
      iops        = 3000
      encrypted   = true
    }
  }

  block_device_mapping {
    device_name = "/dev/sdl"
    ebs {
      volume_size = 6300
      volume_type = "gp3"
      iops        = 3000
      encrypted   = true
    }
  }

  block_device_mapping {
    device_name = "/dev/sdm"
    ebs {
      volume_size = 6400
      volume_type = "gp3"
      iops        = 3000
      encrypted   = true
    }
  }

  block_device_mapping {
    device_name = "/dev/sdn"
    ebs {
      volume_size = 6500
      volume_type = "gp3"
      iops        = 3000
      encrypted   = true
    }
  }

  block_device_mapping {
    device_name = "/dev/sdo"
    ebs {
      volume_size = 6600
      volume_type = "gp3"
      iops        = 3000
      encrypted   = true
    }
  }

  block_device_mapping {
    device_name = "/dev/sdp"
    ebs {
      volume_size = 6700
      volume_type = "gp3"
      iops        = 3000
      encrypted   = true
    }
  }

  block_device_mapping {
    device_name = "/dev/sdq"
    ebs {
      volume_size = 6800
      volume_type = "gp3"
      iops        = 3000
      encrypted   = true
    }
  }

  block_device_mapping {
    device_name = "/dev/sdr"
    ebs {
      volume_size = 6900
      volume_type = "gp3"
      iops        = 3000
      encrypted   = true
    }
  }

  block_device_mapping {
    device_name = "/dev/sds"
    ebs {
      volume_size = 7000
      volume_type = "gp3"
      iops        = 3000
      encrypted   = true
    }
  }

  block_device_mapping {
    device_name = "/dev/sdt"
    ebs {
      volume_size = 7100
      volume_type = "gp3"
      iops        = 3000
      encrypted   = true
    }
  }

  block_device_mapping {
    device_name = "/dev/sdu"
    ebs {
      volume_size = 7200
      volume_type = "gp3"
      iops        = 3000
      encrypted   = true
    }
  }

  block_device_mapping {
    device_name = "/dev/sdv"
    ebs {
      volume_size = 7300
      volume_type = "gp3"
      iops        = 3000
      encrypted   = true
    }
  }

  block_device_mapping {
    device_name = "/dev/sdw"
    ebs {
      volume_size = 7400
      volume_type = "gp3"
      iops        = 3000
      encrypted   = true
    }
  }

  block_device_mapping {
    device_name = "/dev/sdx"
    ebs {
      volume_size = 7500
      volume_type = "gp3"
      iops        = 3000
      encrypted   = true
    }
  }

  block_device_mapping {
    device_name = "/dev/sdy"
    ebs {
      volume_size = 7600
      volume_type = "gp3"
      iops        = 3000
      encrypted   = true
    }
  }

  block_device_mapping {
    device_name = "/dev/sdz"
    ebs {
      volume_size = 7700
      volume_type = "gp3"
      iops        = 3000
      encrypted   = true
    }
  }

  block_device_mapping {
    device_name = "/dev/sda"
    ebs {
      volume_size = 7800
      volume_type = "gp3"
      iops        = 3000
      encrypted   = true
    }
  }

  block_device_mapping {
    device_name = "/dev/sdb"
    ebs {
      volume_size = 7900
      volume_type = "gp3"
      iops        = 3000
      encrypted   = true
    }
  }

  block_device_mapping {
    device_name = "/dev/sdc"
    ebs {
      volume_size = 8000
      volume_type = "gp3"
      iops        = 3000
      encrypted   = true
    }
  }

  block_device_mapping {
    device_name = "/dev/sdd"
    ebs {
      volume_size = 8100
      volume_type = "gp3"
      iops        = 3000
      encrypted   = true
    }
  }

  block_device_mapping {
    device_name = "/dev/sde"
    ebs {
      volume_size = 8200
      volume_type = "gp3"
      iops        = 3000
      encrypted   = true
    }
  }

  block_device_mapping {
    device_name = "/dev/sdf"
    ebs {
      volume_size = 8300
      volume_type = "gp3"
      iops        = 3000
      encrypted   = true
    }
  }

  block_device_mapping {
    device_name = "/dev/sdg"
    ebs {
      volume_size = 8400
      volume_type = "gp3"
      iops        = 3000
      encrypted   = true
    }
  }

  block_device_mapping {
    device_name = "/dev/sdh"
    ebs {
      volume_size = 8500
      volume_type = "gp3"
      iops        = 3000
      encrypted   = true
    }
  }

  block_device_mapping {
    device_name = "/dev/sdi"
    ebs {
      volume_size = 8600
      volume_type = "gp3"
      iops        = 3000
      encrypted   = true
    }
  }

  block_device_mapping {
    device_name = "/dev/sdj"
    ebs {
      volume_size = 8700
      volume_type = "gp3"
      iops        = 3000
      encrypted   = true
    }
  }

  block_device_mapping {
    device_name = "/dev/sdk"
    ebs {
      volume_size = 8800
      volume_type = "gp3"
      iops        = 3000
      encrypted   = true
    }
  }

  block_device_mapping {
    device_name = "/dev/sdl"
    ebs {
      volume_size = 8900
      volume_type = "gp3"
      iops        = 3000
      encrypted   = true
    }
  }

  block_device_mapping {
    device_name = "/dev/sdm"
    ebs {
      volume_size = 9000
      volume_type = "gp3"
      iops        = 3000
      encrypted   = true
    }
  }

  block_device_mapping {
    device_name = "/dev/sdn"
    ebs {
      volume_size = 9100
      volume_type = "gp3"
      iops        = 3000
      encrypted   = true
    }
  }

  block_device_mapping {
    device_name = "/dev/sdo"
    ebs {
      volume_size = 9200
      volume_type = "gp3"
      iops        = 3000
      encrypted   = true
    }
  }

  block_device_mapping {
    device_name = "/dev/sdp"
    ebs {
      volume_size = 9300
      volume_type = "gp3"
      iops        = 3000
      encrypted   = true
    }
  }

  block_device_mapping {
    device_name = "/dev/sdq"
    ebs {
      volume_size = 9400
      volume_type = "gp3"
      iops        = 3000
      encrypted   = true
    }
  }

  block_device_mapping {
    device_name = "/dev/sdr"
    ebs {
      volume_size = 9500
      volume_type = "gp3"
      iops        = 3000
      encrypted   = true
    }
  }

  block_device_mapping {
    device_name = "/dev/sds"
    ebs {
      volume_size = 9600
      volume_type = "gp3"
      iops        = 3000
      encrypted   = true
    }
  }

  block_device_mapping {
    device_name = "/dev/sdt"
    ebs {
      volume_size = 9700
      volume_type = "gp3"
      iops        = 3000
      encrypted   = true
    }
  }

  block_device_mapping {
    device_name = "/dev/sdu"
    ebs {
      volume_size = 9800
      volume_type = "gp3"
      iops        = 3000
      encrypted   = true
    }
  }

  block_device_mapping {
    device_name = "/dev/sdv"
    ebs {
      volume_size = 9900
      volume_type = "gp3"
      iops        = 3000
      encrypted   = true
    }
  }

  block_device_mapping {
    device_name = "/dev/sdw"
    ebs {
      volume_size = 10000
      volume_type = "gp3"
      iops        = 3000
      encrypted   = true
    }
  }

  block_device_mapping {
    device_name = "/dev/sdx"
    ebs {
      volume_size = 10100
      volume_type = "gp3"
      iops        = 3000
      encrypted   = true
    }
  }

  block_device_mapping {
    device_name = "/dev/sdy"
    ebs {
      volume_size = 10200
      volume_type = "gp3"
      iops        = 3000
      encrypted   = true
    }
  }

  block_device_mapping {
    device_name = "/dev/sdz"
    ebs {
      volume_size = 10300
      volume_type = "gp3"
      iops        = 3000
      encrypted   = true
    }
  }

  block_device_mapping {
    device_name = "/dev/sda"
    ebs {
      volume_size = 10400
      volume_type = "gp3"
      iops        = 3000
      encrypted   = true
    }
  }

  block_device_mapping {
    device_name = "/dev/sdb"
    ebs {
      volume_size = 10500
      volume_type = "gp3"
      iops        = 3000
      encrypted   = true
    }
  }

  block_device_mapping {
    device_name = "/dev/sdc"
    ebs {
      volume_size = 10600
      volume_type = "gp3"
      iops        = 3000
      encrypted   = true
    }
  }

  block_device_mapping {
    device_name = "/dev/sdd"
    ebs {
      volume_size = 10700
      volume_type = "gp3"
      iops        = 3000
      encrypted   = true
    }
  }

  block_device_mapping {
    device_name = "/dev/sde"
    ebs {
      volume_size = 10800
      volume_type = "gp3"
      iops        = 3000
      encrypted   = true
    }
  }

  block_device_mapping {
    device_name = "/dev/sdf"
    ebs {
      volume_size = 10900
      volume_type = "gp3"
      iops        = 3000
      encrypted   = true
    }
  }

  block_device_mapping {
    device_name = "/dev/sdg"
    ebs {
      volume_size = 11000
      volume_type = "gp3"
      iops        = 3000
      encrypted   = true
    }
  }

  block_device_mapping {
    device_name = "/dev/sdh"
    ebs {
      volume_size = 11100
      volume_type = "gp3"
      iops        = 3000
      encrypted   = true
    }
  }

  block_device_mapping {
    device_name = "/dev/sdi"
    ebs {
      volume_size = 11200
      volume_type = "gp3"
      iops        = 3000
      encrypted   = true
    }
  }

  block_device_mapping {
    device_name = "/dev/sdj"
    ebs {
      volume_size = 11300
      volume_type = "gp3"
      iops        = 3000
      encrypted   = true
    }
  }

  block_device_mapping {
    device_name = "/dev/sdk"
    ebs {
      volume_size = 11400
      volume_type = "gp3"
      iops        = 3000
      encrypted   = true
    }
  }

  block_device_mapping {
    device_name = "/dev/sdl"
    ebs {
      volume_size = 11500
      volume_type = "gp3"
      iops        = 3000
      encrypted   = true
    }
  }

  block_device_mapping {
    device_name = "/dev/sdm"
    ebs {
      volume_size = 11600
      volume_type = "gp3"
      iops        = 3000
      encrypted   = true
    }
  }

  block_device_mapping {
    device_name = "/dev/sdn"
    ebs {
      volume_size = 11700
      volume_type = "gp3"
      iops        = 3000
      encrypted   = true
    }
  }

  block_device_mapping {
    device_name = "/dev/sdo"
    ebs {
      volume_size = 11800
      volume_type = "gp3"
      iops        = 3000
      encrypted   = true
    }
  }

  block_device_mapping {
    device_name = "/dev/sdp"
    ebs {
      volume_size = 11900
      volume_type = "gp3"
      iops        = 3000
      encrypted   = true
    }
  }

  block_device_mapping {
    device_name = "/dev/sdq"
    ebs {
      volume_size = 12