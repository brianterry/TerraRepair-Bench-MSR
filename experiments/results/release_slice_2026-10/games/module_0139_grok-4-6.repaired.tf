terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

resource "aws_vpc" "sagemaker" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_default_security_group" "default" {
  vpc_id = aws_vpc.sagemaker.id
}

resource "aws_cloudwatch_log_group" "flow_log" {
  name = "/aws/vpc/sagemaker-flow-logs"
}

data "aws_iam_policy_document" "flow-log-assume-role-policy" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "flow_log" {
  name               = "flow_log_role"
  assume_role_policy = data.aws_iam_policy_document.flow-log-assume-role-policy.json
}

data "aws_iam_policy_document" "flow-log-policy" {
  statement {
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "flow_log" {
  name   = "flow_log_policy"
  role   = aws_iam_role.flow_log.id
  policy = data.aws_iam_policy_document.flow-log-policy.json
}

resource "aws_flow_log" "sagemaker" {
  iam_role_arn    = aws_iam_role.flow_log.arn
  log_destination = aws_cloudwatch_log_group.flow_log.arn
  traffic_type    = "REJECT"
  vpc_id          = aws_vpc.sagemaker.id
}

resource "aws_kms_key" "sagemaker" {
  description         = "KMS key for SageMaker notebook encryption"
  enable_key_rotation = true
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

  root_access            = "Disabled"
  direct_internet_access = "Disabled"
  kms_key_id             = aws_kms_key.sagemaker.arn

  instance_metadata_service_configuration {
    minimum_instance_metadata_service_version = "2"
  }

  subnet_id       = aws_subnet.sagemaker.id
  security_groups = [aws_security_group.allow_tls.id]
}