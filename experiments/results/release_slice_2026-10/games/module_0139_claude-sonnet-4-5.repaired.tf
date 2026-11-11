terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

resource "aws_vpc" "sagemaker" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_subnet" "sagemaker" {
  vpc_id     = aws_vpc.sagemaker.id
  cidr_block = "10.0.1.0/24"
}

resource "aws_security_group" "allow_tls" {
  name        = "allow_tls"
  description = "Allow TLS inbound traffic"
  vpc_id      = aws_vpc.sagemaker.id

  ingress {
    description = "TLS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.sagemaker.cidr_block]
  }
}

resource "aws_default_security_group" "default" {
  vpc_id = aws_vpc.sagemaker.id
}

resource "aws_kms_key" "sagemaker" {
  description             = "KMS key for SageMaker encryption"
  deletion_window_in_days = 10
}

resource "aws_cloudwatch_log_group" "vpc_flow_log" {
  name = "/aws/vpc/sagemaker-flow-logs"
}

resource "aws_iam_role" "vpc_flow_log" {
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

resource "aws_iam_role_policy" "vpc_flow_log" {
  name = "vpc-flow-log-policy"
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
        Effect = "Allow"
        Resource = "*"
      }
    ]
  })
}

resource "aws_flow_log" "sagemaker" {
  iam_role_arn    = aws_iam_role.vpc_flow_log.arn
  log_destination = aws_cloudwatch_log_group.vpc_flow_log.arn
  traffic_type    = "REJECT"
  vpc_id          = aws_vpc.sagemaker.id
}

data "aws_iam_policy_document" "instance-assume-role-policy" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "sagemaker" {
  name               = "instance_role"
  path               = "/system/"
  assume_role_policy = data.aws_iam_policy_document.instance-assume-role-policy.json
}

resource "aws_sagemaker_notebook_instance" "ni" {
  name          = "roger-notebook-instance"
  role_arn      = aws_iam_role.sagemaker.arn
  instance_type = "ml.t2.medium"
  
  root_access = "Disabled"
  direct_internet_access = "Disabled"
  kms_key_id = aws_kms_key.sagemaker.id
  instance_metadata_service_configuration {
    minimum_imds_version = "2"
  }

  subnet_id = aws_subnet.sagemaker.id
  security_groups = [aws_security_group.allow_tls.id]
}