terraform {
  required_version = ">= 0.12.0"
}

variable "letters" {
  description = "a list of letters"
  default = ["a", "b", "c"]
}

output "upper-case-list" {
  value = [for l in var.letters: upper(l)]
}

output "upper-case-map" {
  value = {for l in var.letters: l => upper(l)}
}


terraform {
  required_version = ">= 0.12.0"
}

provider "aws" {
  region = "us-east-1"
}

resource "aws_vpc" "my_vpc" {
  cidr_block = "172.16.0.0/16"

  tags = {
    Name = "tf-0.12-for-example"
  }
}

resource "aws_default_security_group" "default" {
  vpc_id = aws_vpc.my_vpc.id
}

resource "aws_cloudwatch_log_group" "vpc_flow_log" {
  name = "/aws/vpc/tf-0.12-for-example-flow-log"
}

resource "aws_iam_role" "vpc_flow_log" {
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
  role = aws_iam_role.vpc_flow_log.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Effect   = "Allow"
        Resource = "*"
      }
    ]
  })
}

resource "aws_flow_log" "my_vpc" {
  iam_role_arn    = aws_iam_role.vpc_flow_log.arn
  log_destination = aws_cloudwatch_log_group.vpc_flow_log.arn
  traffic_type    = "REJECT"
  vpc_id          = aws_vpc.my_vpc.id
}

resource "aws_subnet" "my_subnet" {
  vpc_id = aws_vpc.my_vpc.id
  cidr_block = "172.16.10.0/24"

  tags = {
    Name = "tf-0.12-for-example"
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

resource "aws_iam_role" "ubuntu" {
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

resource "aws_iam_instance_profile" "ubuntu" {
  role = aws_iam_role.ubuntu.name
}

resource "aws_instance" "ubuntu" {
  count = 3
  ami = data.aws_ami.ubuntu_14_04.image_id
  instance_type = "t3.micro"
  associate_public_ip_address = false
  subnet_id = aws_subnet.my_subnet.id
  ebs_optimized = true
  monitoring = true
  iam_instance_profile = aws_iam_instance_profile.ubuntu.name

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  root_block_device {
    encrypted = true
  }

  tags = {
    Name  = format("terraform-0.12-for-demo-%d", count.index)
  }
}

output "private_addresses_old" {
  value = aws_instance.ubuntu.*.private_dns
}

output "private_addresses_full_splat" {
  value = [ aws_instance.ubuntu[*].private_dns ]
}

output "private_addresses_new" {
  value = [
    for instance in aws_instance.ubuntu:
    instance.private_dns
  ]
}

output "ips_with_list_interpolation" {
  value = [
    for instance in aws_instance.ubuntu:
    (instance.public_ip != "" ? list(instance.private_ip, instance.public_ip) : list(instance.private_ip))
  ]
}

output "ips_with_list_in_brackets" {
  value = [
    for instance in aws_instance.ubuntu:
    (instance.public_ip != "" ? [instance.private_ip, instance.public_ip] : [instance.private_ip])
  ]
}