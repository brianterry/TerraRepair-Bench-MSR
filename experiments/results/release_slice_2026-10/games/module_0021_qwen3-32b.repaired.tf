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
  ami           = "ami-0fb653ca2d3203ac1"
  instance_type = "t2.micro"
  ebs_optimized = true
  monitoring    = true

  metadata_options {
    http_tokens = "required"
    http_version = "1.0"
  }

  root_block_device {
    encrypted = true
  }

  # Attach the instance profile
  iam_instance_profile = aws_iam_instance_profile.instance.name
}

# Create an IAM role
resource "aws_iam_role" "instance" {
  name_prefix        = var.name
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}

# Allow the IAM role to be assumed by EC2 instances
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

# Attach the EC2 admin permissions to the IAM role
resource "aws_iam_role_policy" "example" {
  role   = aws_iam_role.instance.id
  policy = data.aws_iam_policy_document.ec2_admin_permissions.json
}

# Create an IAM policy that grants EC2 admin permissions
data "aws_iam_policy_document" "ec2_admin_permissions" {
  statement {
    effect    = "Allow"
    actions   = ["ec2:*"]
    resources = ["arn:aws:ec2:*:*:instance/*", "arn:aws:ec2:*:*:volume/*", "arn:aws:ec2:*:*:snapshot/*"]
  }
}

# Create an instance profile with the IAM role attached
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

# ---------------------------------------------------------------------------------------------------------------------
# OPTIONAL PARAMETERS
# These parameters have reasonable defaults.
# ---------------------------------------------------------------------------------------------------------------------

variable "name" {
  description = "The name used to namespace all the resources created by this module"
  type        = string
  default     = "ec2-iam-role-example"
}