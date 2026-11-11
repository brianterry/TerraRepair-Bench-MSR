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

resource "aws_flow_log" "sagemaker" {
  iam_role_arn    = aws_iam_role.sagemaker.arn
  log_destination = aws_cloudwatch_log_group.sagemaker.arn
  traffic_type    = "REJECT"
  vpc_id          = aws_vpc.sagemaker.id
}

resource "aws_cloudwatch_log_group" "sagemaker" {
  name = "sagemaker-flow-logs"
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

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "default" {
  name        = "default"
  description = "Default security group"
  vpc_id      = aws_vpc.sagemaker.id

  ingress {
    from_port = -1
    to_port   = -1
    protocol  = -1
    self      = true
  }

  egress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

data "aws_iam_policy_document" "instance-assume-role-policy" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com", "sagemaker.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "sagemaker" {
  name               = "instance_role"
  path               = "/system/"
  assume_role_policy = data.aws_iam_policy_document.instance-assume-role-policy.json
}

resource "aws_kms_key" "sagemaker" {
  description             = "SageMaker KMS key"
  deletion_window_in_days = 10
}

resource "aws_sagemaker_notebook_instance" "ni" {
  name          = "roger-notebook-instance"
  role_arn      = aws_iam_role.sagemaker.arn
  instance_type = "ml.t2.medium"
  kms_key_id    = aws_kms_key.sagemaker.arn
  root_access   = "Disabled"
  direct_internet_access = "Disabled"

  subnet_id = aws_subnet.sagemaker.id
  security_groups = [aws_security_group.allow_tls.id]
}

resource "aws_sagemaker_notebook_instance_lifecycle_configuration" "ni" {
  name = "sagemaker-lifecycle-config"

  on_create {
    content = "{\"CreateNotebookInstance\":{\"ImdsSupport\":\"v2\"}}"
  }
}