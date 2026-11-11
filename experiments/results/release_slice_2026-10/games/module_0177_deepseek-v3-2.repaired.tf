data "aws_availability_zones" "ph-azs" {
  state                    = "available"
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

resource "aws_vpc" "ph-vpc" {
  cidr_block              = var.vpc_cidr
  enable_dns_support      = "true"
  enable_dns_hostnames    = "true"
  tags                    = {
    Name                  = "ph-vpc"
  }
}

resource "aws_default_security_group" "ph-default-sg" {
  vpc_id = aws_vpc.ph-vpc.id
  ingress = []
  egress = []
  tags = {
    Name = "ph-default-sg"
  }
}

resource "aws_flow_log" "ph-vpc-flow-log" {
  vpc_id                  = aws_vpc.ph-vpc.id
  traffic_type            = "REJECT"
  log_destination_type    = "cloud-watch-logs"
  log_destination         = aws_cloudwatch_log_group.ph-vpc-flow-log-group.arn
  iam_role_arn           = aws_iam_role.ph-vpc-flow-log-role.arn
  tags                    = {
    Name                  = "ph-vpc-flow-log"
  }
}

resource "aws_cloudwatch_log_group" "ph-vpc-flow-log-group" {
  name                    = "/aws/vpc/${aws_vpc.ph-vpc.id}/flow-log"
  retention_in_days       = 7
  tags                    = {
    Name                  = "ph-vpc-flow-log-group"
  }
}

resource "aws_iam_role" "ph-vpc-flow-log-role" {
  name                    = "ph-vpc-flow-log-role"
  assume_role_policy      = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "vpc-flow-logs.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "ph-vpc-flow-log-policy" {
  name                    = "ph-vpc-flow-log-policy"
  role                    = aws_iam_role.ph-vpc-flow-log-role.id
  policy                  = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams"
      ],
      "Resource": "*"
    }
  ]
}
EOF
}

resource "aws_s3_bucket" "ph-bucket" {
  bucket                  = "${var.name_prefix}-${random_string.ph-random.result}"
  acl                     = "private"
  versioning {
    enabled = true
  }
  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        kms_master_key_id = aws_kms_key.ph-kmscmk-s3.arn
        sse_algorithm     = "aws:kms"
      }
    }
  }
  force_destroy           = true
  policy                  = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "KMS Manager",
      "Effect": "Allow",
      "Principal": {
        "AWS": ["${data.aws_iam_user.ph-kmsmanager.arn}"]
      },
      "Action": [
        "s3:*"
      ],
      "Resource": [
        "arn:aws:s3:::${var.name_prefix}-${random_string.ph-random.result}",
        "arn:aws:s3:::${var.name_prefix}-${random_string.ph-random.result}/*"
      ]
    },
    {
      "Sid": "Instance List",
      "Effect": "Allow",
      "Principal": {
        "AWS": ["${aws_iam_role.ph-instance-iam-role.arn}"]
      },
      "Action": [
        "s3:ListBucket"
      ],
      "Resource": ["arn:aws:s3:::${var.name_prefix}-${random_string.ph-random.result}"]
    },
    {
      "Sid": "Instance Get",
      "Effect": "Allow",
      "Principal": {
        "AWS": ["${aws_iam_role.ph-instance-iam-role.arn}"]
      },
      "Action": [
        "s3:GetObject",
        "s3:GetObjectVersion"
      ],
      "Resource": ["arn:aws:s3:::${var.name_prefix}-${random_string.ph-random.result}/*"]
    },
    {
      "Sid": "Instance Put",
      "Effect": "Allow",
      "Principal": {
        "AWS": ["${aws_iam_role.ph-instance-iam-role.arn}"]
      },
      "Action": [
        "s3:PutObject",
        "s3:PutObjectAcl"
      ],
      "Resource": [
        "arn:aws:s3:::${var.name_prefix}-${random_string.ph-random.result}/ssm/*",
        "arn:aws:s3:::${var.name_prefix}-${random_string.ph-random.result}/wireguard/*"
      ]
    }
  ]
}
POLICY
  logging {
    target_bucket = aws_s3_bucket.ph-bucket-logging.id
    target_prefix = "logs/"
  }
  lifecycle_rule {
    id      = "log-expiration"
    enabled = true
    expiration {
      days = 7
    }
  }
  replication_configuration {
    role = aws_iam_role.ph-s3-replication-role.arn
    rules {
      id     = "replication"
      status = "Enabled"
      destination {
        bucket        = aws_s3_bucket.ph-bucket-replica.arn
        storage_class = "STANDARD"
      }
    }
  }
}

resource "aws_s3_bucket" "ph-bucket-logging" {
  bucket                  = "${var.name_prefix}-${random_string.ph-random.result}-logging"
  acl                     = "log-delivery-write"
  force_destroy           = true
  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  }
}

resource "aws_s3_bucket" "ph-bucket-replica" {
  bucket                  = "${var.name_prefix}-${random_string.ph-random.result}-replica"
  acl                     = "private"
  versioning {
    enabled = true
  }
  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  }
  force_destroy           = true
}

resource "aws_iam_role" "ph-s3-replication-role" {
  name                    = "ph-s3-replication-role"
  assume_role_policy      = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "s3.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "ph-s3-replication-policy" {
  name                    = "ph-s3-replication-policy"
  role                    = aws_iam_role.ph-s3-replication-role.id
  policy                  = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetReplicationConfiguration",
        "s3:ListBucket"
      ],
      "Resource": [
        "${aws_s3_bucket.ph-bucket.arn}"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObjectVersion",
        "s3:GetObjectVersionAcl"
      ],
      "Resource": [
        "${aws_s3_bucket.ph-bucket.arn}/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:ReplicateObject",
        "s3:ReplicateDelete"
      ],
      "Resource": [
        "${aws_s3_bucket.ph-bucket-replica.arn}/*"
      ]
    }
  ]
}
EOF
}

resource "aws_s3_bucket_notification" "ph-bucket-notification" {
  bucket = aws_s3_bucket.ph-bucket.id
  topic {
    topic_arn     = aws_sns_topic.ph-s3-event-topic.arn
    events        = ["s3:ObjectCreated:*"]
  }
}

resource "aws_sns_topic" "ph-s3-event-topic" {
  name = "ph-s3-event-topic"
}

resource "aws_s3_bucket_public_access_block" "ph-bucket-pubaccessblock" {
  bucket                  = aws_s3_bucket.ph-bucket.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_instance" "ph-instance" {
  ami                     = aws_ami_copy.ph-latest-vendor-ami-with-cmk.id
  instance_type           = var.instance_type
  iam_instance_profile    = aws_iam_instance_profile.ph-instance-profile.name
  key_name                = aws_key_pair.ph-instance-key.key_name
  subnet_id               = aws_subnet.ph-pubnet.id
  private_ip              = var.pubnet_instance_ip
  vpc_security_group_ids  = [aws_security_group.ph-pubsg.id]
  tags                    = {
    Name                    = "${var.name_prefix}-cloudblock",
    cloudblock              = "True"
  }
  user_data               = <<EOF
#!/bin/bash
# replace systemd-resolved with static dns derived from dhcp
DNS_SERVER=$(resolvectl | awk -F ': ' '/DNS Servers/ { print $2 }')
systemctl disable systemd-resolved
systemctl stop systemd-resolved
rm -f /etc/resolv.conf
tee /etc/resolv.conf << EOM
nameserver $DNS_SERVER
options edns0
search ec2.internal
EOM
EOF
  root_block_device {
    volume_size             = var.instance_vol_size
    volume_type             = "standard"
    encrypted               = "true"
    kms_key_id              = aws_kms_key.ph-kmscmk-ec2.arn
  }
  metadata_options {
    http_endpoint          = "enabled"
    http_tokens            = "required"
    http_put_response_hop_limit = 2
  }
  ebs_optimized           = true
  monitoring              = true
  depends_on              = [aws_iam_role_policy_attachment.ph-iam-attach-ssm, aws_iam_role_policy_attachment.ph-iam-attach-s3]
}

resource "aws_instance" "ph-instance2" {
  ami                     = aws_ami_copy.ph-latest-vendor-ami-with-cmk.id
  instance_type           = var.instance_type
  iam_instance_profile    = aws_iam_instance_profile.ph-instance-profile.name
  key_name                = aws_key_pair.ph-instance-key.key_name
  subnet_id               = aws_subnet.ph-pubnet.id
  private_ip              = var.pubnet_instance_ip2
  vpc_security_group_ids  = [aws_security_group.ph-pubsg.id]
  tags                    = {
    Name                    = "${var.name_prefix}-cloudblock",
    cloudblock             = "True"
  }
  user_data               = <<EOF
#!/bin/bash
# replace systemd-resolved with static dns derived from dhcp
DNS_SERVER=$(resolvectl | awk -F ': ' '/DNS Servers/ { print $2 }')
systemctl disable systemd-resolved
systemctl stop systemd-resolved
rm -f /etc/resolv.conf
tee /etc/resolv.conf << EOM
nameserver $DNS_SERVER
options edns0
search ec2.internal
EOM
EOF
  root_block_device {
    volume_size             = var.instance_vol_size
    volume_type             = "standard"
    encrypted               = "true"
    kms_key_id              = aws_kms_key.ph-kmscmk-ec2.arn
  }
  metadata_options {
    http_endpoint          = "enabled"
    http_tokens            = "required"
    http_put_response_hop_limit = 2
  }
  ebs_optimized           = true
  monitoring              = true
  depends_on              = [aws_iam_role_policy_attachment.ph-iam-attach-ssm, aws_iam_role_policy_attachment.ph-iam-attach-s3]
}

resource "aws_security_group_rule" "ph-pubsg-out-tcp" {
  security_group_id       = aws_security_group.ph-pubsg.id
  type                    = "egress"
  description             = "OUT TO WORLD - TCP"
  from_port               = 0
  to_port                 = 65535
  protocol                = "tcp"
  cidr_blocks             = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]
}

resource "aws_security_group_rule" "ph-pubsg-out-udp" {
  security_group_id       = aws_security_group.ph-pubsg.id
  type                    = "egress"
  description             = "OUT TO WORLD - UDP"
  from_port               = 0
  to_port                 = 65535
  protocol                = "udp"
  cidr_blocks             = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]
}