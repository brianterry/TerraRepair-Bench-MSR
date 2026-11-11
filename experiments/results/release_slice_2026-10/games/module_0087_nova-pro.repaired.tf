provider "aws" {
  region = "us-east-1"
}

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.50"
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

  flow_log_configuration {
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

resource "aws_iam_role_policy_attachment" "vpc_flow_logs_policy" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/VPCFlowLogsServiceRolePolicy"
  role       = aws_iam_role.vpc_flow_logs.name
}

resource "aws_security_group" "client" {
  name   = "client"
  vpc_id = aws_vpc.main.id

  ingress {
    description = "Allow SSH access from specific IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["192.168.0.0/24"]
  }

  egress {
    description = "Allow specific outbound traffic"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["192.168.0.0/24"]
  }
}

resource "aws_instance" "client" {
  ami           = data.aws_ami.ubuntu_jammy.id
  key_name      = "devops"
  instance_type = "t3a.xlarge"
  subnet_id     = aws_subnet.public_us_east_1a.id

  vpc_security_group_ids = [
    aws_security_group.client.id
  ]

  tags = {
    Name          = "client.antonputra.pvt"
    service       = "client"
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
    device_name = "/dev/sdf"
    volume_size = 10
    encrypted   = true
  }

  monitoring {
    enabled = true
  }
}

resource "aws_subnet" "public_us_east_1a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.64.0/19"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = false

  tags = {
    "Name"                       = "public-us-east-1a"
    "kubernetes.io/role/elb"     = "1"
    "kubernetes.io/cluster/demo" = "owned"
  }
}

resource "aws_subnet" "public_us_east_1b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.96.0/19"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = false

  tags = {
    "Name"                       = "public-us-east-1b"
    "kubernetes.io/role/elb"     = "1"
    "kubernetes.io/cluster/demo" = "owned"
  }
}

resource "aws_eks_cluster" "demo" {
  name     = "demo"
  version  = "1.24"
  role_arn = aws_iam_role.demo.arn

  vpc_config {
    subnet_ids = [
      aws_subnet.private_us_east_1a.id,
      aws_subnet.private_us_east_1b.id,
      aws_subnet.public_us_east_1a.id,
      aws_subnet.public_us_east_1b.id
    ]
  }

  logging {
    cluster_logging {
      enabled_types = [
        "api",
        "audit",
        "authenticator",
        "controllerManager",
        "scheduler"
      ]
    }
  }

  encryption_config {
    resources = ["secrets"]
  }

  public_access {
    enabled = false
  }

  depends_on = [aws_iam_role_policy_attachment.demo_amazon_eks_cluster_policy]
}