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

  enable_flow_logs = true
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

resource "aws_kms_key" "sagemaker" {
  description             = "KMS key for SageMaker"
  deletion_window_in_days = 7
}

resource "aws_sagemaker_notebook_instance" "ni" {
  name                   = "roger-notebook-instance"
  role_arn               = aws_iam_role.sagemaker.arn
  instance_type          = "ml.t2.medium"
  root_access            = "Disabled"
  direct_internet_access = "Disabled"
  kms_key_id             = aws_kms_key.sagemaker.arn
  subnet_id              = aws_subnet.sagemaker.id
  security_groups        = [aws_security_group.allow_tls.id]
  metadata_service_config {
    metadata_access_state = "Enabled"
    metadata_access_method {
      metadata_access_method = "IMDSv2"
    }
  }
}