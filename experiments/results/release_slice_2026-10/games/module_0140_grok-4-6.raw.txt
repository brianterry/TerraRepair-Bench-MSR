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
}

resource "aws_cloudwatch_log_group" "flow_log" {
  name = "tf-0.12-fce-example-flow-log"
}

resource "aws_iam_role" "flow_log" {
  name = "tf-0.12-fce-example-flow-log-role"

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

resource "aws_iam_role_policy" "flow_log" {
  name = "tf-0.12-fce-example-flow-log-policy"
  role = aws_iam_role.flow_log.id

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

resource "aws_flow_log" "my_vpc" {
  iam_role_arn    = aws_iam_role.flow_log.arn
  log_destination = aws_cloudwatch_log_group.flow_log.arn
  traffic_type    = "REJECT"
  vpc_id          = aws_vpc.my_vpc.id
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

resource "aws_iam_role" "foo" {
  name = "tf-0.12-fce-ec2-instance-role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_instance_profile" "foo" {
  name = "tf-0.12-fce-ec2-instance-profile"
  role = aws_iam_role.foo.name
}

resource "aws_instance" "foo" {
  ami = data.aws_ami.ubuntu_14_04.image_id
  instance_type = "t2.micro"
  ebs_optimized = true
  monitoring = true
  iam_instance_profile = aws_iam_instance_profile.foo.name

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  root_block_device {
    encrypted = true
  }

  tags = {
    Name = "tf-0.12-fce-ec2-instance"
  }

  network_interface {
    network_interface_id = aws_network_interface.foo.id
    device_index = 0
  }
}

output "private_dns" {
  value = aws_instance.foo.private_dns
}