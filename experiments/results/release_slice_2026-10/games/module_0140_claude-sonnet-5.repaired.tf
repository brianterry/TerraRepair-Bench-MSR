terraform {
  required_version = ">= 0.12.0"
}

provider "aws" {
  region = "us-west-2"
}

variable "vpc_name" {
  description = "name of the VPC"
  default = "tf-0.12-fce-example"
}

resource "aws_vpc" "my_vpc" {
  cidr_block = "172.16.0.0/16"

  tags = {
    Name = var.vpc_name
  }
}

resource "aws_default_security_group" "default" {
  vpc_id = aws_vpc.my_vpc.id

  ingress = []
  egress  = []
}

resource "aws_cloudwatch_log_group" "vpc_flow_log" {
  name              = "/vpc/flow-logs/${var.vpc_name}"
  retention_in_days = 90
}

resource "aws_iam_role" "vpc_flow_log_role" {
  name = "vpc-flow-log-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "vpc-flow-logs.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "vpc_flow_log_policy" {
  name = "vpc-flow-log-policy"
  role = aws_iam_role.vpc_flow_log_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_flow_log" "my_vpc_flow_log" {
  log_destination      = aws_cloudwatch_log_group.vpc_flow_log.arn
  iam_role_arn          = aws_iam_role.vpc_flow_log_role.arn
  vpc_id                = aws_vpc.my_vpc.id
  traffic_type          = "REJECT"
}

resource "aws_subnet" "my_subnet" {
  vpc_id = aws_vpc.my_vpc.id
  cidr_block = "172.16.10.0/24"

  tags = {
    Name = "tf-0.12-fce-example"
  }
}

resource "aws_network_interface" "foo" {
  subnet_id = aws_subnet.my_subnet.id
  private_ips = ["172.16.10.100"]
  
  tags = {
    Name = "tf-0.12-fce-primary_network_interface"
  }
}

data "aws_ami" "ubuntu_14_04" {
  most_recent      = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm/ubuntu-trusty-14.04-amd64-server-*"]
  }

  owners     = ["099720109477"]
}

resource "aws_iam_role" "ec2_role" {
  name = "tf-0.12-fce-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "tf-0.12-fce-ec2-profile"
  role = aws_iam_role.ec2_role.name
}

resource "aws_instance" "foo" {
  ami = data.aws_ami.ubuntu_14_04.image_id
  instance_type = "t2.micro"

  tags = {
    Name = "tf-0.12-fce-ec2-instance"
  }

  network_interface {
    network_interface_id = aws_network_interface.foo.id
    device_index = 0
  }

  iam_instance_profile = aws_iam_instance_profile.ec2_profile.name
  monitoring            = true
  ebs_optimized          = true

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  root_block_device {
    encrypted = true
  }
}

output "private_dns" {
  value = aws_instance.foo.private_dns
}