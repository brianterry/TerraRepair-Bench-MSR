locals {
  common_tags = {
    Company     = var.company_name
    Project     = var.project
    Environment = var.environment
    BillingCode = var.billing_code
  }
  naming_prefix = "${var.project}-${var.environment}"
}

/*
This Terraform configuration sets up a basic web application on AWS using an EC2 instance running Nginx.
It includes the necessary networking components such as a VPC, subnet, internet gateway, and security groups.
AWS credentials are required to apply this configuration and can be set using environment variables or the AWS CLI.
*/

##################################################################################
# PROVIDERS
##################################################################################

provider "aws" {
  region = var.aws_region
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
  cidr_block           = var.vpc_cidr_block
  enable_dns_hostnames = var.vpc_enable_dns_hostnames

  tags = merge(local.common_tags, { Name = lower("${local.naming_prefix}-vpc") })
}

resource "aws_default_security_group" "app" {
  vpc_id = aws_vpc.app.id

  tags = merge(local.common_tags, { Name = lower("${local.naming_prefix}-default-sg") })
}

resource "aws_cloudwatch_log_group" "vpc_flow_log" {
  name = "/aws/vpc/${local.naming_prefix}-flow-logs"
}

resource "aws_iam_role" "vpc_flow_log" {
  name = "${local.naming_prefix}-vpc-flow-log-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "vpc-flow-logs.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy" "vpc_flow_log" {
  name = "${local.naming_prefix}-vpc-flow-log-policy"
  role = aws_iam_role.vpc_flow_log.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams"
      ]
      Effect   = "Allow"
      Resource = "*"
    }]
  })
}

resource "aws_flow_log" "app" {
  iam_role_arn    = aws_iam_role.vpc_flow_log.arn
  log_destination = aws_cloudwatch_log_group.vpc_flow_log.arn
  traffic_type    = "REJECT"
  vpc_id          = aws_vpc.app.id
}

resource "aws_internet_gateway" "app" {
  vpc_id = aws_vpc.app.id
  tags   = local.common_tags
}

resource "aws_subnet" "public_subnet1" {
  cidr_block              = var.vpc_subnet_cidr
  vpc_id                  = aws_vpc.app.id
  map_public_ip_on_launch = false
  tags                    = merge(local.common_tags, { Name = lower("${local.naming_prefix}-public-subnet1") })
}

# ROUTING #
resource "aws_route_table" "app" {
  vpc_id = aws_vpc.app.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.app.id
  }

  tags = merge(local.common_tags, { Name = lower("${local.naming_prefix}-rtb") })
}

resource "aws_route_table_association" "app_subnet1" {
  subnet_id      = aws_subnet.public_subnet1.id
  route_table_id = aws_route_table.app.id
}

# SECURITY GROUPS #
# Nginx security group 
resource "aws_security_group" "nginx_sg" {
  name        = lower("${local.naming_prefix}-nginx_sg")
  description = "Security group for Nginx web server allowing HTTP access"
  vpc_id      = aws_vpc.app.id

  # HTTP access from anywhere
  ingress {
    description = "Allow HTTP access"
    from_port   = var.http_port
    to_port     = var.http_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # outbound internet access
  egress {
    description = "Allow outbound traffic within VPC"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr_block]
  }

  tags = local.common_tags
}

resource "aws_iam_role" "nginx1" {
  name = "${local.naming_prefix}-nginx1-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_instance_profile" "nginx1" {
  name = "${local.naming_prefix}-nginx1-profile"
  role = aws_iam_role.nginx1.name
}

# INSTANCES #
resource "aws_instance" "nginx1" {
  ami                         = nonsensitive(data.aws_ssm_parameter.amzn2_linux.value)
  instance_type               = var.ec2_instance_type
  subnet_id                   = aws_subnet.public_subnet1.id
  vpc_security_group_ids      = [aws_security_group.nginx_sg.id]
  iam_instance_profile        = aws_iam_instance_profile.nginx1.name
  user_data_replace_on_change = true
  ebs_optimized               = true
  monitoring                  = true
  tags                        = merge(local.common_tags, { Name = lower("${local.naming_prefix}-nginx1") })

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  root_block_device {
    encrypted = true
  }

  user_data = templatefile("./templates/startup_script.tpl", {
    environment = var.environment
  })

}


output "aws_instance_public_dns" {
  description = "Public DNS hostname of the EC2 instance"
  value       = "http://${aws_instance.nginx1.public_dns}:${var.http_port}"
}

output "vpc_id" {
  description = "ID of the created VPC"
  value       = aws_vpc.app.id
}

output "public_subnet_id" {
  description = "ID of the public subnet"
  value       = aws_subnet.public_subnet1.id
}

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket = "<SET TO YOUR BUCKET NAME>"
    region = "us-east-1"
    
  }
}

variable "aws_region" {
  description = "The AWS region to deploy resources in"
  type        = string
  default     = "us-east-1"
}

variable "vpc_cidr_block" {
  description = "The CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "vpc_enable_dns_hostnames" {
  description = "Enable DNS hostnames in the VPC"
  type        = bool
  default     = true
}

variable "vpc_subnet_cidr" {
  description = "The CIDR block for the public subnet"
  type        = string
  default     = "10.0.0.0/24"
}

variable "map_public_ip_on_launch" {
  description = "Whether to map public IPs on launch for the subnet"
  type        = bool
  default     = false
}

variable "http_port" {
  description = "The HTTP port for the application"
  type        = number
}

variable "ec2_instance_type" {
  description = "The type of EC2 instance to launch"
  type        = string
}

variable "company_name" {
  description = "The name of the company"
  type        = string
  default     = "Globomantics"
}

variable "project" {
  description = "The name of the project"
  type        = string
}

variable "environment" {
  description = "The environment for the deployment (e.g., dev, staging, prod)"
  type        = string
}

variable "billing_code" {
  description = "The billing code for the project"
  type        = string
}