provider "aws" {
  region = "us-east-1"
}

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.48"
    }
  }
}

resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "main"
  }
}

resource "aws_default_security_group" "default" {
  vpc_id = aws_vpc.main.id

  ingress = []
  egress  = []

  tags = {
    Name = "default"
  }
}

resource "aws_flow_log" "vpc_flow_log" {
  vpc_id                 = aws_vpc.main.id
  traffic_type          = "REJECT"
  log_destination_type  = "cloud-watch-logs"
  log_destination       = aws_cloudwatch_log_group.vpc_flow_log_group.arn
  iam_role_arn          = aws_iam_role.vpc_flow_log_role.arn
}

resource "aws_cloudwatch_log_group" "vpc_flow_log_group" {
  name = "vpc-flow-log-group"
}

resource "aws_iam_role" "vpc_flow_log_role" {
  name = "vpc-flow-log-role"

  assume_role_policy = <<EOF
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

resource "aws_iam_role_policy_attachment" "vpc_flow_log_policy" {
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess"
  role       = aws_iam_role.vpc_flow_log_role.name
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "igw"
  }
}

resource "aws_subnet" "public_us_east_1a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.0.0/19"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = false

  tags = {
    "Name" = "public-us-east-1a"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "public"
  }
}

resource "aws_route_table_association" "public_us_east_1a" {
  subnet_id      = aws_subnet.public_us_east_1a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "nginx" {
  name        = "allow-nginx-traffic"
  description = "Security group for nginx instance"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "nginx-sg"
  }
}

resource "aws_security_group_rule" "ingress_http" {
  security_group_id = aws_security_group.nginx.id
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "Allow HTTP traffic"
}

resource "aws_security_group_rule" "ingress_https" {
  security_group_id = aws_security_group.nginx.id
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "Allow HTTPS traffic"
}

resource "aws_security_group_rule" "ingress_metrics" {
  security_group_id = aws_security_group.nginx.id
  type              = "ingress"
  from_port         = 8080
  to_port           = 8080
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "Allow metrics traffic"
}

resource "aws_security_group_rule" "ingress_prometheus" {
  security_group_id = aws_security_group.nginx.id
  type              = "ingress"
  from_port         = 9090
  to_port           = 9090
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "Allow Prometheus traffic"
}

resource "aws_security_group_rule" "ingress_grafana" {
  security_group_id = aws_security_group.nginx.id
  type              = "ingress"
  from_port         = 3000
  to_port           = 3000
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "Allow Grafana traffic"
}

resource "aws_security_group_rule" "egress_restricted" {
  security_group_id = aws_security_group.nginx.id
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["10.0.0.0/16"]
  description       = "Allow egress within VPC"
}

resource "aws_iam_instance_profile" "nginx" {
  name = "nginx"
  role = aws_iam_role.nginx.name
}

resource "aws_iam_role" "nginx" {
  name = "nginx"

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

resource "aws_iam_role_policy_attachment" "amazon_ssm_managed_instance_core" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  role       = aws_iam_role.nginx.name
}

data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"]
}

resource "aws_instance" "web" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t3.micro"

  associate_public_ip_address = false

  subnet_id              = aws_subnet.public_us_east_1a.id
  vpc_security_group_ids = [aws_security_group.nginx.id]
  iam_instance_profile   = aws_iam_instance_profile.nginx.name

  ebs_optimized = true
  monitoring    = true

  metadata_options {
    http_endpoint          = "enabled"
    http_tokens            = "required"
    http_put_response_hop_limit = 2
    instance_metadata_tags = "enabled"
  }

  root_block_device {
    encrypted = true
  }

  tags = {
    Name = "nginx"
  }
}