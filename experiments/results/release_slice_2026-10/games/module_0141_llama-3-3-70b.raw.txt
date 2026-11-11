terraform {
  required_version = ">= 0.12.0"
}

# List of letters
variable "letters" {
  description = "a list of letters"
  default = ["a", "b", "c"]
}

# Convert letters to upper-case as list
output "upper-case-list" {
  value = [for l in var.letters: upper(l)]
}

# Convert letters to upper-case as map
output "upper-case-map" {
  value = {for l in var.letters: l => upper(l)}
}

provider "aws" {
  region = "us-east-1"
}

resource "aws_vpc" "my_vpc" {
  cidr_block = "172.16.0.0/16"
  enable_flow_log = true
  tags = {
    Name = "tf-0.12-for-example"
  }
}

resource "aws_flow_log" "example" {
  iam_role_arn    = aws_iam_role.flow_log.arn
  log_destination = aws_cloudwatch_log_group.example.arn
  traffic_type    = "REJECT"
  vpc_id          = aws_vpc.my_vpc.id
}

resource "aws_cloudwatch_log_group" "example" {
  name = "example-log-group"
}

resource "aws_iam_role" "flow_log" {
  name        = "flow-log-role"
  description = "Role for flow log"

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

resource "aws_iam_role_policy" "flow_log" {
  name   = "flow-log-policy"
  role   = aws_iam_role.flow_log.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Effect = "Allow"
        Resource = aws_cloudwatch_log_group.example.arn
      }
    ]
  })
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

resource "aws_instance" "ubuntu" {
  count = 3
  ami = data.aws_ami.ubuntu_14_04.image_id
  instance_type = "t2.micro"
  associate_public_ip_address = ( count.index == 1 ? true : false)
  subnet_id = aws_subnet.my_subnet.id
  vpc_security_group_ids = [aws_security_group.example.id]
  iam_instance_profile {
    name = aws_iam_instance_profile.example.name
  }
  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }
  ebs_optimized = true
  monitoring = true

  tags = {
    Name  = format("terraform-0.12-for-demo-%d", count.index)
  }

  root_block_device {
    encrypted = true
  }
}

resource "aws_security_group" "example" {
  name        = "example-sg"
  description = "Example security group"
  vpc_id      = aws_vpc.my_vpc.id

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "example-sg"
  }
}

resource "aws_iam_instance_profile" "example" {
  name = "example-iam-instance-profile"
  role = aws_iam_role.example.name
}

resource "aws_iam_role" "example" {
  name        = "example-iam-role"
  description = "Example IAM role"

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

resource "aws_iam_role_policy" "example" {
  name   = "example-iam-role-policy"
  role   = aws_iam_role.example.id
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