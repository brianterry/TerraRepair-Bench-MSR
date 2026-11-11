terraform {
  required_version = ">= 1.0.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  region = "us-east-2"
}

resource "aws_instance" "example" {
  ami                         = "ami-0fb653ca2d3203ac1"
  instance_type               = "t2.micro"
  iam_instance_profile        = aws_iam_instance_profile.instance.name
  monitoring                  = true
  ebs_optimized               = true
  metadata_options {
    http_tokens    = "required"
    http_endpoint  = "enabled"
    http_put_response_hop_limit = 1
  }
  root_block_device {
    volume_size = 8
    volume_type = "gp2"
    encrypted   = true
  }
}

resource "aws_iam_role" "instance" {
  name_prefix        = var.name
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}

data "aws_iam_policy_document" "assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "example" {
  role   = aws_iam_role.instance.id
  policy = data.aws_iam_policy_document.ec2_admin_permissions.json
}

data "aws_iam_policy_document" "ec2_admin_permissions" {
  statement {
    effect    = "Allow"
    actions   = [
      "ec2:Describe*",
      "ec2:Get*",
      "ec2:CreateTags",
      "ec2:DeleteTags",
      "ec2:RunInstances",
      "ec2:TerminateInstances",
      "ec2:StopInstances",
      "ec2:StartInstances"
    ]
    resources = ["*"]
  }
  statement {
    effect    = "Deny"
    actions   = [
      "ec2:AuthorizeSecurityGroupIngress",
      "ec2:RevokeSecurityGroupIngress",
      "ec2:ModifyInstanceAttribute",
      "ec2:AssociateAddress",
      "ec2:DisassociateAddress",
      "ec2:AttachVolume",
      "ec2:DetachVolume",
      "ec2:CreateVolume",
      "ec2:DeleteVolume",
      "ec2:CreateSnapshot",
      "ec2:DeleteSnapshot",
      "ec2:CreateImage",
      "ec2:DeregisterImage",
      "ec2:CreateKeyPair",
      "ec2:DeleteKeyPair",
      "ec2:DescribeKeyPairs",
      "ec2:ImportKeyPair",
      "ec2:CreateSecurityGroup",
      "ec2:DeleteSecurityGroup",
      "ec2:DescribeSecurityGroups",
      "ec2:CreateTags",
      "ec2:DeleteTags",
      "ec2:RunInstances",
      "ec2:TerminateInstances",
      "ec2:StopInstances",
      "ec2:StartInstances"
    ]
    resources = ["*"]
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_iam_instance_profile" "instance" {
  role = aws_iam_role.instance.name
}

output "instance_id" {
  value       = aws_instance.example.id
  description = "The ID of the EC2 instance"
}

output "instance_ip" {
  value       = aws_instance.example.public_ip
  description = "The public IP of the EC2 instance"
}

output "iam_role_arn" {
  value       = aws_iam_role.instance.arn
  description = "The ARN of the IAM role"
}

variable "name" {
  description = "The name used to namespace all the resources created by this module"
  type        = string
  default     = "ec2-iam-role-example"
}