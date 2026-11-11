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

  ingress = []
  egress  = []
}

resource "aws_iam_role" "flow_log_role" {
  name = "flow_log_role"

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

resource "aws_iam_role_policy" "flow_log_policy" {
  name = "flow_log_policy"
  role = aws_iam_role.flow_log_role.id

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

resource "aws_cloudwatch_log_group" "vpc_flow_log" {
  name = "/vpc/flow-log/my_vpc"
}

resource "aws_flow_log" "my_vpc_flow_log" {
  iam_role_arn    = aws_iam_role.flow_log_role.arn
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

resource "aws_iam_role" "ubuntu_role" {
  name = "ubuntu_instance_role"

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

resource "aws_iam_instance_profile" "ubuntu_profile" {
  name = "ubuntu_instance_profile"
  role = aws_iam_role.ubuntu_role.name
}

resource "aws_instance" "ubuntu" {
  count = 3
  ami = data.aws_ami.ubuntu_14_04.image_id
  instance_type = "t2.micro"
  associate_public_ip_address = false
  subnet_id = aws_subnet.my_subnet.id
  monitoring = true
  ebs_optimized = true
  iam_instance_profile = aws_iam_instance_profile.ubuntu_profile.name

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

# This uses the old splat expression
output "private_addresses_old" {
  value = aws_instance.ubuntu.*.private_dns
}

# This uses the new full splat operator (*)
output "private_addresses_full_splat" {
  value = [ aws_instance.ubuntu[*].private_dns ]
}

# This uses the new for expression
output "private_addresses_new" {
  value = [
    for instance in aws_instance.ubuntu:
    instance.private_dns
  ]
}

# This uses the new conditional expression
# that can work with lists
# This uses the list interpolation function
output "ips_with_list_interpolation" {
  value = [
    for instance in aws_instance.ubuntu:
    (instance.public_ip != "" ? list(instance.private_ip, instance.public_ip) : list(instance.private_ip))
  ]
}

# It also works with lists in [x, y, z] form
output "ips_with_list_in_brackets" {
  value = [
    for instance in aws_instance.ubuntu:
    (instance.public_ip != "" ? [instance.private_ip, instance.public_ip] : [instance.private_ip])
  ]
}