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

  flow_log {
    traffic_type = "REJECT"
    log_destination_type = "cloud-watch-logs"
  }

  default_security_group_allow {
    inbound = []
    outbound = []
  }
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

  root_access = "Disabled"
  direct_internet_access = "Disabled"
  kms_key_id = "alias/aws/sagemaker"

  subnet_id = aws_subnet.sagemaker.id
  security_groups = [aws_security_group.allow_tls.id]

  lifecycle_config {
    on_create = <<EOF
      aws s3 cp s3://my-bucket/my-notebook-config.json /home/ec2-user/SageMaker/my-notebook-config.json
    EOF
  }

  platform_identifier = "ml.t2.medium"
  encryption_no_new_groups = true
  disable_internet_access = true
  disable_root_access = true
  kms_key_arn = "arn:aws:kms:us-east-1:123456789012:key/1234abcd-12ab-34cd-56ef-1234567890ab"
}