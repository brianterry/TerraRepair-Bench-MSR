locals {
  common-tags = {
    "project"          = "${upper("${substr("${var.aws-profile}", 0, 3)}")}"
    "platform"         = "${upper("${substr("${var.aws-profile}", 0, 3)}")}"
    "environment-type" = var.environment
    "business-domain"  = "na"
    "cost-center"      = "na"
    "tier"             = "private"
    "application"      = var.application
  }
}

data "aws_caller_identity" "current" {}
resource "random_uuid" "randuuid" {}

data "local_file" "msk-keypair-public" {
  filename = "${path.module}/keys/MSK-Keypair.pub"
}

resource "aws_key_pair" "MSK-Keypair-ec2-keypair" {
  key_name   = var.key_name
  public_key = data.local_file.msk-keypair-public.content
}

output "msk-user-keypair" {
  value = aws_key_pair.MSK-Keypair-ec2-keypair.key_name
}

resource "aws_kms_key" "pca-kms" {
  description         = "KMS Key for encrypting the PCA s3 bucket"
  enable_key_rotation = "true"
  policy              = <<EOF
{
    "Version": "2012-10-17",
    "Id": "key-policy-with-replication",
    "Statement": [
          {
            "Sid": "Account usage of KMS Key",
            "Effect": "Allow",
            "Principal": {
                "AWS": "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
            },
            "Action": "kms:*",
            "Resource": "*"
        }
      ]
}
EOF
}

resource "aws_kms_alias" "pca-kims-alias" {
  name          = "alias/pca-kims-alias"
  target_key_id = aws_kms_key.pca-kms.key_id
}

resource "random_id" "kms" {
  byte_length = 2
}
resource "aws_kms_key" "msk-kms-key" {
  description         = "KMS Key for encrypting the EBS volumes"
  enable_key_rotation = "true"
  policy              = <<EOF
{
    "Version": "2012-10-17",
    "Id": "key-policy-with-replication",
    "Statement": [
          {
            "Sid": "Account usage of KMS Key",
            "Effect": "Allow",
            "Principal": {
                "AWS": "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
            },
            "Action": "kms:*",
            "Resource": "*"
        }
      ]
}
EOF
}

resource "aws_kms_alias" "msk-kms-alias" {
  name          = "alias/msk-kms-alias-${random_id.kms.hex}"
  target_key_id = aws_kms_key.msk-kms-key.key_id
}

resource "aws_kms_key" "cloudwatch-kms-key" {
  description         = "KMS Key for encrypting CloudWatch logs"
  enable_key_rotation = "true"
  policy              = <<EOF
{
    "Version": "2012-10-17",
    "Id": "key-policy-cloudwatch",
    "Statement": [
          {
            "Sid": "Account usage of KMS Key",
            "Effect": "Allow",
            "Principal": {
                "AWS": "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
            },
            "Action": "kms:*",
            "Resource": "*"
        },
        {
            "Sid": "Allow CloudWatch Logs",
            "Effect": "Allow",
            "Principal": {
                "Service": "logs.${var.aws_region}.amazonaws.com"
            },
            "Action": [
                "kms:Encrypt",
                "kms:Decrypt",
                "kms:ReEncrypt*",
                "kms:GenerateDataKey*",
                "kms:CreateGrant",
                "kms:DescribeKey"
            ],
            "Resource": "*",
            "Condition": {
                "ArnLike": {
                    "kms:EncryptionContext:aws:logs:arn": "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:*"
                }
            }
        }
      ]
}
EOF
}

resource "aws_iam_instance_profile" "KafkaClientIAM_Profile" {
  name = "KafkaClientIAM_profile"
  role = aws_iam_role.KafkaClientIAM_Role.name
}

resource "aws_iam_role" "KafkaClientIAM_Role" {
  name = "KafkaClientIAM_Role"
  path = "/"


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

resource "aws_iam_role_policy_attachment" "Kafka-Client-IAM-role-att1" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonMSKFullAccess"
  role       = aws_iam_role.KafkaClientIAM_Role.name
}

resource "aws_iam_role_policy_attachment" "Kafka-Client-IAM-role-att2" {
  policy_arn = "arn:aws:iam::aws:policy/AWSCloudFormationReadOnlyAccess"
  role       = aws_iam_role.KafkaClientIAM_Role.name
}

resource "aws_instance" "Kafka-Client-EC2-Instance" {
  ami                    = var.msk_ami
  instance_type          = var.msk_instance_type
  key_name               = var.key_name
  vpc_security_group_ids = [aws_security_group.KafkaClientInstanceSG.id]
  user_data              = file("./kafka-client-msk.sh")
  subnet_id              = aws_subnet.private_subnet[1].id
  iam_instance_profile   = aws_iam_instance_profile.KafkaClientIAM_Profile.name
  ebs_optimized          = true
  monitoring             = true
  
  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }

  root_block_device {
    encrypted   = true
    kms_key_id  = aws_kms_key.msk-kms-key.arn
    volume_type = "gp2"
    volume_size = 100
  }

  ebs_block_device {
    device_name           = "/dev/xvda"
    volume_size           = 100
    volume_type           = "gp2"
    delete_on_termination = true
    encrypted             = true
    kms_key_id            = aws_kms_key.msk-kms-key.arn
  }

  tags = merge(
    local.common-tags,
    map(
      "Name", "Kafka-Client-EC2-Instance"
    )
  )
}

output "IP" {
  value       = aws_instance.Kafka-Client-EC2-Instance.private_ip
  description = "The private IP address of the Kafka-Client-EC2-Instance instance."
}


resource "aws_cloudwatch_log_group" "cloudwatch_log_group" {
  name              = "msk_cluster_cloudwatch_group-${random_uuid.randuuid.result}"
  retention_in_days = 365
  kms_key_id        = aws_kms_key.cloudwatch-kms-key.arn
}

resource "aws_msk_configuration" "msk_cluster_config" {
  kafka_versions = [var.msk_cluster_version]
  name           = "msk-${lower(var.environment)}-cluster-cfg-${random_uuid.randuuid.result}"
  server_properties = <<PROPERTIES
auto.create.topics.enable = true
delete.topic.enable = true
PROPERTIES
}

resource "aws_msk_cluster" "msk_cluster" {
  count                  = length(var.private_subnet_cidrs)
  cluster_name           = "msk-${lower(var.environment)}-cluster-${random_uuid.randuuid.result}"
  kafka_version          = var.msk_cluster_version
  number_of_broker_nodes = var.broker_nodes

  broker_node_group_info {
    instance_type   = var.msk_cluster_instance_type
    ebs_volume_size = var.msk_ebs_volume_size
    client_subnets = [
      "${aws_subnet.private_subnet.0.id}",
      "${aws_subnet.private_subnet.1.id}",
      "${aws_subnet.private_subnet.2.id}"
    ]
    security_groups = [aws_security_group.KafkaClusterSG.id]
  }

  configuration_info {
    arn      = aws_msk_configuration.msk_cluster_config.arn
    revision = 1
  }
  
  encryption_info {
    encryption_at_rest_kms_key_arn = aws_kms_key.msk-kms-key.arn
    encryption_in_transit {
      client_broker = "TLS"
      in_cluster    = true
    }
  }

  enhanced_monitoring = var.monitoring_type

  logging_info {
    broker_logs {
      cloudwatch_logs {
        enabled   = true
        log_group = aws_cloudwatch_log_group.cloudwatch_log_group.name
      }
    }
  }

  tags = merge(
    local.common-tags,
    map(
      "Name", "msk-${lower(var.environment)}-cluster"
    )
  )
}

output "zookeeper_connect_string" {
  value = aws_msk_cluster.msk_cluster.*.zookeeper_connect_string
}

output "bootstrap_brokers" {
  description = "Plaintext connection host:port pairs"
  value       = aws_msk_cluster.msk_cluster.*.bootstrap_brokers
}

output "bootstrap_brokers_tls" {
  description = "TLS connection host:port pairs"
  value       = aws_msk_cluster.msk_cluster.*.bootstrap_brokers_tls
}

resource "aws_internet_gateway" "main-igw" {
  vpc_id = aws_vpc.msk_vpc.id
  tags = merge(
    local.common-tags,
    map(
      "Name", "MSK-IGW",
      "Description", "Internet Gateway"
    )
  )
}

resource "aws_eip" "nat" {
  domain = "vpc"
  depends_on = [aws_internet_gateway.main-igw]
}

resource "aws_eip_association" "nat_eip_assoc" {
  allocation_id = aws_eip.nat.id
  network_interface_id = aws_nat_gateway.main-natgw.network_interface_id
}

resource "aws_nat_gateway" "main-natgw" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public_subnet[0].id
  tags = merge(
    local.common-tags,
    map(
      "Name", "MSK-NatGateway",
      "Description", "NAT Gateway"
    )
  )
}

resource "aws_route_table" "PublicRouteTable" {
  vpc_id = aws_vpc.msk_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main-igw.id
  }
  tags = merge(
    local.common-tags,
    map(
      "Name", "MSK-Public-Routetable",
      "Description", "Public-Routetable"
    )
  )

}

resource "aws_route_table" "PrivateRouteTable" {
  vpc_id = aws_vpc.msk_vpc.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main-natgw.id
  }
  tags = merge(
    local.common-tags,
    map(
      "Name", "MSK-Private-Routetable",
      "Description", "Private-Routetable"
    )
  )
}

resource "aws_route_table_association" "route_Publicsubnet" {
  subnet_id      = element(aws_subnet.public_subnet.*.id, count.index)
  count          = length(var.public_subnet_cidrs)
  route_table_id = aws_route_table.PublicRouteTable.id
}

resource "aws_route_table_association" "route_Privatesubnet" {
  subnet_id      = element(aws_subnet.private_subnet.*.id, count.index)
  count          = length(var.private_subnet_cidrs)
  route_table_id = aws_route_table.PrivateRouteTable.id
}


provider "aws" {
  profile = var.aws-profile
  region  = var.aws_region
}


resource "aws_security_group" "KafkaClusterSG" {
  name        = "msk-${lower(var.environment)}-sg-${random_uuid.randuuid.result}"
  description = "Allow TLS inbound traffic"
  vpc_id      = aws_vpc.msk_vpc.id

  ingress {
    description = "Zookeeper port"
    from_port   = 2181
    to_port     = 2181
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  ingress {
    description = "Kafka TLS port"
    from_port   = 9094
    to_port     = 9094
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  ingress {
    description = "Kafka plaintext port"
    from_port   = 9092
    to_port     = 9092
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "Allow outbound to VPC"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }

  tags = merge(
    local.common-tags,
    map(
      "Name", "msk-${lower(var.environment)}-sg-${random_uuid.randuuid.result}"
    )
  )
}

resource "aws_security_group" "KafkaClientInstanceSG" {
  name        = "KafkaClientInstanceSG"
  description = "Allow TLS inbound traffic"
  vpc_id      = aws_vpc.msk_vpc.id

  ingress {
    description = "SSH port"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "Allow outbound to VPC"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }

  tags = merge(
    local.common-tags,
    map(
      "Name", "KafkaClientInstanceSG"
    )
  )
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_subnet" "private_subnet" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.msk_vpc.id
  cidr_block        = element(split(",", join(",", var.private_subnet_cidrs)), count.index)
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = merge(
    local.common-tags,
    map(
      "Name", "MSK-${lower(var.environment)}-private-subnet-${count.index + 1}",
      "Description", "${lower(var.environment)} private subnet - ${count.index + 1}"
    )
  )

}



resource "aws_subnet" "public_subnet" {
  count             = length(var.public_subnet_cidrs)
  vpc_id            = aws_vpc.msk_vpc.id
  cidr_block        = element(split(",", join(",", var.public_subnet_cidrs)), count.index)
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = merge(
    local.common-tags,
    map(
      "Name", "msk-${lower(var.environment)}-public-subnet-${count.index + 1}",
      "Description", "${lower(var.environment)} private subnet - ${count.index + 1}"
    )
  )

}


variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "aws-profile" {
  description = "Local AWS Profile Name "
  type        = string
}

variable "environment" {
  description = "AWS Environment"
  type        = string
}

variable "application" {
  type    = string
  default = "acm"
}

variable "vpc_cidr" {
  description = "VPC CIDR"
  type        = string
}

variable "private_subnet_cidrs" {
  description = "Private subnet  - CIDR"
  type        = list
}
variable "public_subnet_cidrs" {
  description = "Private subnet  - CIDR"
  type        = list
}

variable "msk_cluster_version" {
  type    = string
  default = "2.4.1.1"
}

variable "broker_nodes" {
  default = 3
}

variable "msk_cluster_instance_type" {
  type    = string
  default = "kafka.m5.large"
}

variable "msk_ebs_volume_size" {
  default = 100
}

variable "encryption_type" {
  type    = string
  default = "TLS_PLAINTEXT"
}

variable "monitoring_type" {
  type    = string
  default = "PER_BROKER"
}

variable "key_name" {
  type    = string
  default = "MSK-Keypair"
}

variable "msk_instance_type" {
  type    = string
  default = "m5.large"
}

variable "msk_ami" {
  type    = string
  default = "ami-04d29b6f966df1537"
}

resource "aws_vpc" "msk_vpc" {
  cidr_block = var.vpc_cidr
  tags = merge(
    local.common-tags,
    map(
      "Name", "msk-${lower(var.environment)}-vpc",
      "Description", "VPC for creating MSK resources",
    )
  )
}

resource "aws_default_security_group" "default" {
  vpc_id = aws_vpc.msk_vpc.id
}

resource "aws_flow_log" "msk_vpc_flow_log" {
  iam_role_arn    = aws_iam_role.vpc_flow_log_role.arn
  log_destination = aws_cloudwatch_log_group.vpc_flow_log_group.arn
  traffic_type    = "REJECT"
  vpc_id          = aws_vpc.msk_vpc.id
}

resource "aws_cloudwatch_log_group" "vpc_flow_log_group" {
  name              = "vpc-flow-log-${random_uuid.randuuid.result}"
  retention_in_days = 365
  kms_key_id        = aws_kms_key.cloudwatch-kms-key.arn
}

resource "aws_iam_role" "vpc_flow_log_role" {
  name = "vpc-flow-log-role-${random_uuid.randuuid.result}"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "",
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

resource "aws_iam_role_policy" "vpc_flow_log_policy" {
  name = "vpc-flow-log-policy-${random_uuid.randuuid.result}"
  role = aws_iam_role.vpc_flow_log_role.id

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams"
      ],
      "Effect": "Allow",
      "Resource": "*"
    }
  ]
}
EOF
}