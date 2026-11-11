/*
This Terraform configuration sets up a basic web application on AWS using an EC2 instance running Nginx.
It includes the necessary networking components such as a VPC, subnet, internet gateway, and security groups.
AWS credentials are required to apply this configuration and can be set using environment variables or the AWS CLI.
*/

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

##################################################################################
# PROVIDERS
##################################################################################

provider "aws" {
  region     = "us-east-1"
}

##################################################################################
# DATA
##################################################################################

data "aws_ssm_parameter" "amzn2_linux" {
  name = "/aws/service/ami-amazon-linux-latest/amzn2-ami-hvm-x86_64-gp2"
}

##################################################################################
# RESOURCES
##################################################################################

# NETWORKING #
resource "aws_vpc" "app" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true

}

resource "aws_default_security_group" "app" {
  vpc_id = aws_vpc.app.id

  ingress {
    description = "Deny all ingress"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = []
  }

  egress {
    description = "Deny all egress"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = []
  }
}

resource "aws_flow_log" "app" {
  vpc_id                   = aws_vpc.app.id
  traffic_type             = "REJECT"
  log_destination_type     = "cloud-watch-logs"
  log_destination          = aws_cloudwatch_log_group.flow_log.arn
  iam_role_arn             = aws_iam_role.flow_log.arn
}

resource "aws_cloudwatch_log_group" "flow_log" {
  name              = "/aws/vpc/flowlog/app"
  retention_in_days = 7
}

resource "aws_iam_role" "flow_log" {
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

resource "aws_iam_role_policy" "flow_log" {
  name = "vpc-flow-log-policy"
  role = aws_iam_role.flow_log.id

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

resource "aws_internet_gateway" "app" {
  vpc_id = aws_vpc.app.id

}

resource "aws_subnet" "public_subnet1" {
  cidr_block              = "10.0.0.0/24"
  vpc_id                  = aws_vpc.app.id
  map_public_ip_on_launch = false
}

# ROUTING #
resource "aws_route_table" "app" {
  vpc_id = aws_vpc.app.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.app.id
  }
}

resource "aws_route_table_association" "app_subnet1" {
  subnet_id      = aws_subnet.public_subnet1.id
  route_table_id = aws_route_table.app.id
}

# SECURITY GROUPS #
# Nginx security group 
resource "aws_security_group" "nginx_sg" {
  name        = "nginx_sg"
  description = "Security group for Nginx web server"
  vpc_id      = aws_vpc.app.id

  # HTTP access from specific CIDR
  ingress {
    description = "HTTP access from specific CIDR"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/8"]
  }

  # outbound internet access to specific ports
  egress {
    description = "HTTPS outbound access"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# INSTANCES #
resource "aws_iam_role" "ec2_role" {
  name = "nginx-ec2-role"

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

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "nginx-ec2-profile"
  role = aws_iam_role.ec2_role.name
}

resource "aws_instance" "nginx1" {
  ami                    = nonsensitive(data.aws_ssm_parameter.amzn2_linux.value)
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.public_subnet1.id
  vpc_security_group_ids = [aws_security_group.nginx_sg.id]
  user_data_replace_on_change = true
  ebs_optimized          = true
  monitoring             = true
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  root_block_device {
    encrypted = true
  }

  user_data = <<EOF
#! /bin/bash
sudo amazon-linux-extras install -y nginx1
sudo service nginx start
sudo rm /usr/share/nginx/html/index.html
sudo cat > /usr/share/nginx/html/index.html << 'WEBSITE'
<html>
<head>
    <title>Taco Team Server</title>
</head>
<body style="background-color:#1F778D">
    <p style="text-align: center;">
        <span style="color:#FFFFFF;">
            <span style="font-size:100px;">Welcome to the website! Have a &#127790;</span>
        </span>
    </p>
</body>
</html>
WEBSITE
EOF

}