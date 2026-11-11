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

resource "aws_flow_log" "my_vpc" {
  iam_role_arn    = aws_iam_role.vpc_flow_log.arn
  log_destination = aws_cloudwatch_log_group.vpc_flow_log.arn
  traffic_type    = "REJECT"
  vpc_id          = aws_vpc.my_vpc.id
}

resource "aws_cloudwatch_log_group" "vpc_flow_log" {
  name = "vpc-flow-log"
}

resource "aws_iam_role" "vpc_flow_log" {
  name        = "vpc-flow-log"
  description = "VPC Flow Log IAM Role"

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

resource "aws_iam_role_policy" "vpc_flow_log" {
  name   = "vpc-flow-log"
  role   = aws_iam_role.vpc_flow_log.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Effect = "Allow"
        Resource = aws_cloudwatch_log_group.vpc_flow_log.arn
      }
    ]
  })
}

resource "aws_security_group" "my_vpc" {
  name        = "my-vpc-sg"
  description = "Default security group for my VPC"
  vpc_id      = aws_vpc.my_vpc.id

  ingress {
    from_port = -1
    to_port   = -1
    protocol  = -1
    self      = true
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "my-vpc-sg"
  }
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

resource "aws_iam_role" "ec2" {
  name        = "ec2"
  description = "EC2 IAM Role"

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

resource "aws_iam_role_policy" "ec2" {
  name   = "ec2"
  role   = aws_iam_role.ec2.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "ec2:*",
        ]
        Effect = "Allow"
        Resource = "*"
      }
    ]
  })
}

resource "aws_instance" "foo" {
  ami = data.aws_ami.ubuntu_14_04.image_id
  instance_type = "t2.micro"
  ebs_optimized = true
  monitoring = true

  metadata_options {
    http_endpoint = "enabled"
    http_tokens = "required"
  }

  tags = {
    Name = "tf-0.12-fce-ec2-instance"
  }

  network_interface {
    network_interface_id = aws_network_interface.foo.id
    device_index = 0
  }

  root_block_device {
    encrypted = true
  }

  iam_role = aws_iam_role.ec2.arn
}

output "private_dns" {
  value = aws_instance.foo.private_dns
}