provider "aws" {
  region = "us-east-1"
}

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.55"
    }
  }
}

resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"

  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "main"
  }

  flow_log {
    traffic_type = "REJECT"
    iam_role_arn = aws_iam_role.vpc_flow_logs.arn
  }
}

resource "aws_iam_role" "vpc_flow_logs" {
  name = "vpc_flow_logs_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Effect = "Allow",
      Principal = {
        Service = "vpc-flow-logs.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy" "vpc_flow_logs" {
  name = "vpc_flow_logs_policy"
  role = aws_iam_role.vpc_flow_logs.name

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      Effect = "Allow",
      Resource = "arn:aws:logs:*:*:*"
    }]
  })
}

resource "aws_security_group" "test" {
  name_prefix = "test"
  description = "Security group for test instance"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
    description = "Allow SSH access from VPC"
  }

  ingress {
    from_port   = 9100
    to_port     = 9100
    protocol    = "tcp"
    security_groups = [aws_eks_cluster.demo.vpc_config[0].cluster_security_group_id]
    description = "Allow Node Exporter Access"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["10.0.0.0/16"]
    description = "Allow all outbound traffic to VPC"
  }
}

resource "aws_instance" "test" {
  ami                    = data.aws_ami.ubuntu_jammy.id
  instance_type          = "t3a.small"
  subnet_id              = aws_subnet.public_us_east_1a.id
  vpc_security_group_ids = [aws_security_group.test.id]
  user_data              = file("scripts/user_data.sh")
  tags                   = {
    Name          = "myapp"
    service       = "myapp"
    node-exporter = "true"
  }

  metadata_options {
    http_tokens = "required"
    http_endpoint = "enabled"
    http_put_response_hop_limit = 1
  }

  root_block_device {
    encrypted = true
  }

  ebs_block_device {
    device_name = "/dev/sda1"
    encrypted   = true
  }
}

resource "aws_subnet" "public_us_east_1a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.64.0/19"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = false

  tags = {
    Name                       = "public-us-east-1a"
    "kubernetes.io/role/elb"   = "1"
    "kubernetes.io/cluster/demo" = "owned"
  }
}

resource "aws_subnet" "public_us_east_1b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.96.0/19"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = false

  tags = {
    Name                       = "public-us-east-1b"
    "kubernetes.io/role/elb"   = "1"
    "kubernetes.io/cluster/demo" = "owned"
  }
}

resource "aws_eks_cluster" "demo" {
  name     = "demo"
  version  = "1.24"
  role_arn = aws_iam_role.demo.arn

  enabled_cluster_log_types = [
    "api",
    "audit",
    "authenticator",
    "controllerManager",
    "scheduler"
  ]

  encryption_config {
    resources = ["secrets"]
  }

  vpc_config {
    subnet_ids = [
      aws_subnet.private_us_east_1a.id,
      aws_subnet.private_us_east_1b.id,
      aws_subnet.public_us_east_1a.id,
      aws_subnet.public_us_east_1b.id
    ]
  }

  endpoint_public_access = false
  endpoint_private_access = true

  depends_on = [aws_iam_role_policy_attachment.demo_amazon_eks_cluster_policy]
}